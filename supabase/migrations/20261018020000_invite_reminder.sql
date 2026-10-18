-- Psst link reminder (owner pick 3A): if nobody has opened a one-person Psst link
-- by day 5, the person who sent it gets one push ("Your Psst hasn't been opened" /
-- "Send it again?") that opens the share sheet with the same link. Once per link,
-- and never once it's been accepted, revoked or has expired. Sent by the hourly
-- weekly-recap run. A deleted account takes its invites with it (on delete cascade).

alter table public.invites add column reminded_at timestamptz;

-- Keeps the hourly scan to links that could still be due.
create index invites_reminder_due_idx on public.invites (created_at)
    where kind = 'psst' and reminded_at is null and uses = 0;

-- Server-only: claims every Psst link that's due a reminder and returns who to
-- push. The claim (reminded_at) happens in the same statement as the read, so two
-- overlapping runs can't both send one; a link claimed while its sender has no
-- device stays claimed (one chance per link).
create function public.invite_reminder_targets() returns jsonb
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
        returning i.inviter_id, i.code
    )
    select coalesce(jsonb_agg(jsonb_build_object(
        'user_id', d.inviter_id,
        'code', d.code,
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
