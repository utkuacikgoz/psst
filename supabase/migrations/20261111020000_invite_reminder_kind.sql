-- Day-5 link reminder (owner pick 13A, 10 Nov 2026): the push now says "Your Psst
-- is still waiting" / "Send it again?" (the server only knows nobody joined, not
-- that nobody opened it), and tells the app which link it is, so a doodle link is
-- shared again with the doodle message: "kind" is "doodle" (a Psst link holding
-- a doodle), "psst" (a plain Psst link) or "code" (a group code; not reminded
-- today). Same targets and once-per-link claim as before.

create or replace function public.invite_reminder_targets() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
    result jsonb;
begin
    with due as (
        update public.invites i set reminded_at = now()
        where i.kind = 'psst'
          and i.reminded_at is null
          and i.uses = 0
          and i.accepted_at is null
          and i.revoked_at is null
          and i.expires_at > now()
          and i.created_at <= now() - interval '5 days'
          -- Only apps that open the share sheet from this push (build 40 and later);
          -- an older app's link waits and is reminded once its sender updates.
          and exists (select 1 from public.profiles pr
                      where pr.id = i.inviter_id and coalesce(pr.app_build, 0) >= 40)
        returning i.inviter_id, i.code,
            case when i.kind = 'code' then 'code' when i.doodle is not null then 'doodle' else 'psst' end as kind
    )
    select coalesce(jsonb_agg(jsonb_build_object(
        'user_id', d.inviter_id,
        'code', d.code,
        'kind', d.kind,
        'sound', p.notification_sound,
        'tokens', coalesce((select jsonb_agg(jsonb_build_object('token', t.token, 'environment', t.environment))
                            from public.device_tokens t where t.user_id = d.inviter_id), '[]'::jsonb))), '[]'::jsonb)
    into result
    from due d
    join public.profiles p on p.id = d.inviter_id;
    return result;
end;
$$;

revoke execute on function public.invite_reminder_targets() from public, anon, authenticated;
grant execute on function public.invite_reminder_targets() to service_role;
