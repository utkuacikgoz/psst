-- 6A (owner pick, 15 Oct 2026): the private numbers dashboard. Counts only: the
-- last 60 days of private.metrics_daily, plus how many accounts exist and how many
-- have Psst+ right now. No ids, names or content. Server-only (service role).
create function public.metrics_report() returns jsonb
language sql stable security definer set search_path = '' as $$
    select jsonb_build_object(
        'generated_at', now(),
        'accounts_now', (select count(*) from public.profiles),
        'plus_now', (select count(*) from private.plus_entitlements where valid_until > now()),
        'days', coalesce((
            select jsonb_agg(jsonb_build_object(
                'day', m.day, 'accounts', m.accounts, 'new_accounts', m.new_accounts,
                'accepted_invites', m.accepted_invites, 'signals', m.signals, 'active_pairs', m.active_pairs,
                'two_way_pairs', m.two_way_pairs, 'first_two_way_pairs', m.first_two_way_pairs,
                'returning_pairs', m.returning_pairs, 'push_failed', m.push_failed,
                'push_no_devices', m.push_no_devices, 'blocks', m.blocks, 'reports', m.reports)
                order by m.day)
            from private.metrics_daily m
            where m.day > current_date - 60), '[]'::jsonb));
$$;

revoke execute on function public.metrics_report() from public, anon, authenticated;
grant execute on function public.metrics_report() to service_role;
