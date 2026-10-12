-- "Kim is in": the inviter hears when someone accepts their invite.
-- Server-only. The accept-invite function calls it once, right after a fresh
-- acceptance; the push carries no message content, only the joiner's name.
create function public.joined_push_targets(p_connection_id uuid) returns jsonb
language sql security definer set search_path = '' as $$
    select jsonb_build_object(
        'connection_id', c.id,
        'joiner_name', j.display_name,
        'sound', r.notification_sound,
        'tokens', coalesce((select jsonb_agg(jsonb_build_object('token', t.token, 'environment', t.environment))
                            from public.device_tokens t where t.user_id = inv.inviter_id), '[]'::jsonb))
    from public.connections c
    join lateral (
        select i.inviter_id, i.accepted_by from public.invites i
        where i.accepted_at is not null
          and i.inviter_id in (c.user_a, c.user_b) and i.accepted_by in (c.user_a, c.user_b)
        order by i.accepted_at desc limit 1
    ) inv on true
    join public.profiles j on j.id = inv.accepted_by
    join public.profiles r on r.id = inv.inviter_id
    where c.id = p_connection_id;
$$;

-- APNs said these tokens are gone (app deleted, device reset).
create function public.remove_device_tokens(p_tokens text[]) returns void
language sql security definer set search_path = '' as $$
    delete from public.device_tokens where token = any (p_tokens);
$$;

revoke execute on function public.joined_push_targets(uuid), public.remove_device_tokens(text[])
    from public, anon, authenticated;
grant execute on function public.joined_push_targets(uuid), public.remove_device_tokens(text[])
    to service_role;
