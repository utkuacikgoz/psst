-- All-time activity without keeping individual Pssts.
-- Each Psst still disappears after 30 days (purge_expired). Alongside it we keep
-- one running count per pair and direction: two numbers per connection, no
-- times, no content. Removing the person, blocking, or deleting your account
-- deletes the counts with the connection.
create table private.pair_counts (
    connection_id uuid not null references public.connections (id) on delete cascade,
    sender_id uuid not null references public.profiles (id) on delete cascade,
    sent bigint not null default 0,
    primary key (connection_id, sender_id)
);
revoke all on private.pair_counts from public, anon, authenticated;

-- Start from what's still kept (the last 30 days).
insert into private.pair_counts (connection_id, sender_id, sent)
select connection_id, sender_id, count(*) from public.signal_events group by connection_id, sender_id;

-- send_signal inserts each event once (retries hit the same id and insert nothing),
-- so counting inserts counts each Psst exactly once.
create function private.count_pair_signal() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
    insert into private.pair_counts (connection_id, sender_id, sent)
    values (new.connection_id, new.sender_id, 1)
    on conflict (connection_id, sender_id) do update set sent = private.pair_counts.sent + 1;
    return null;
end;
$$;

create trigger signal_events_pair_count
    after insert on public.signal_events
    for each row execute function private.count_pair_signal();

-- Your leaderboard: all-time counts, plus this month's from the kept Pssts.
-- p_month_start is the start of the month on the caller's phone (their time zone).
create function public.personal_activity_all(p_month_start timestamptz) returns table (
    connection_id uuid, other_name text,
    sent_all bigint, received_all bigint, sent_month bigint, received_month bigint
) language plpgsql security definer set search_path = '' as $$
declare
    me uuid := private.require_user();
    since timestamptz := greatest(coalesce(p_month_start, now()), now() - interval '32 days');
begin
    return query
    select c.id, p.display_name,
           coalesce((select pc.sent from private.pair_counts pc where pc.connection_id = c.id and pc.sender_id = me), 0),
           coalesce((select pc.sent from private.pair_counts pc where pc.connection_id = c.id and pc.sender_id = p.id), 0),
           (select count(*) from public.signal_events s where s.connection_id = c.id and s.sender_id = me and s.created_at >= since),
           (select count(*) from public.signal_events s where s.connection_id = c.id and s.sender_id = p.id and s.created_at >= since)
    from public.connections c
    join public.profiles p on p.id = case when c.user_a = me then c.user_b else c.user_a end
    where me in (c.user_a, c.user_b) and not private.is_blocked(me, p.id);
end;
$$;

revoke execute on function public.personal_activity_all(timestamptz) from public, anon, authenticated;
grant execute on function public.personal_activity_all(timestamptz) to authenticated;
