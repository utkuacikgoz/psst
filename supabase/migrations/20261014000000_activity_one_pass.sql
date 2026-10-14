-- The leaderboard in one pass: count this month's Pssts for all your connections
-- together instead of two lookups per person, so it stays quick with hundreds of
-- people. Same columns and results as before, so 1.0.4 keeps working.
create or replace function public.personal_activity_all(p_month_start timestamptz) returns table (
    connection_id uuid, other_name text,
    sent_all bigint, received_all bigint, sent_month bigint, received_month bigint
) language plpgsql security definer set search_path = '' as $$
declare
    me uuid := private.require_user();
    since timestamptz := greatest(coalesce(p_month_start, now()), now() - interval '32 days');
begin
    return query
    with mine as (
        select c.id as cid, case when c.user_a = me then c.user_b else c.user_a end as other_id
        from public.connections c
        where me in (c.user_a, c.user_b)
    ), month_counts as (
        select s.connection_id as cid,
               count(*) filter (where s.sender_id = me) as sent,
               count(*) filter (where s.sender_id <> me) as received
        from public.signal_events s
        join mine m on m.cid = s.connection_id
        where s.created_at >= since
        group by s.connection_id
    ), totals as (
        select pc.connection_id as cid,
               max(pc.sent) filter (where pc.sender_id = me) as sent,
               max(pc.sent) filter (where pc.sender_id <> me) as received
        from private.pair_counts pc
        join mine m on m.cid = pc.connection_id
        group by pc.connection_id
    )
    select m.cid, p.display_name,
           coalesce(t.sent, 0)::bigint, coalesce(t.received, 0)::bigint,
           coalesce(mc.sent, 0)::bigint, coalesce(mc.received, 0)::bigint
    from mine m
    join public.profiles p on p.id = m.other_id
    left join month_counts mc on mc.cid = m.cid
    left join totals t on t.cid = m.cid
    where not private.is_blocked(me, m.other_id);
end;
$$;
