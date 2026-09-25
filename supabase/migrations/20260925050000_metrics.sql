-- Measurement without an analytics SDK. The server already holds everything
-- needed except one fact: whether a person has notifications switched off,
-- which the app now reports as a single yes/no.
--
-- A daily job stores aggregate counts only (no ids, names or content) in
-- private.metrics_daily, so trends survive the 30-day signal purge. Read it
-- in the Supabase SQL editor; clients have no access. See docs/METRICS.md.

alter table public.profiles add column notifications_enabled boolean;  -- null: not reported yet
alter table public.connections add column first_two_way_at timestamptz;

create function public.set_notification_status(p_enabled boolean) returns void
language plpgsql security definer set search_path = '' as $$
declare
    me uuid := private.require_user();
begin
    update public.profiles set notifications_enabled = p_enabled where id = me;
end;
$$;

-- Marks the moment a pair first exchanged in both directions.
create function private.mark_first_two_way() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
    update public.connections set first_two_way_at = new.created_at
    where id = new.connection_id and first_two_way_at is null
      and exists (select 1 from public.signal_events
                  where connection_id = new.connection_id and sender_id = new.recipient_id);
    return null;
end;
$$;

create trigger signal_events_first_two_way
after insert on public.signal_events
for each row execute function private.mark_first_two_way();

create table private.metrics_daily (
    day date primary key,
    accounts int not null,             -- profiles existing at snapshot time
    new_accounts int not null,
    accepted_invites int not null,
    connections int not null,          -- existing at snapshot time
    signals int not null,
    active_pairs int not null,         -- pairs with any signal that day
    two_way_pairs int not null,        -- pairs where both sides sent that day
    first_two_way_pairs int not null,  -- pairs whose first two-way exchange was that day
    returning_pairs int not null,      -- two-way that day, and first two-way on an earlier day
    push_failed int not null,
    push_no_devices int not null,
    blocks int not null,
    reports int not null,
    notifications_off int not null,    -- people who reported notifications off (at snapshot time)
    notifications_reported int not null,
    created_at timestamptz not null default now()
);

create function private.snapshot_metrics(p_day date) returns void
language sql security definer set search_path = '' as $$
    with day_signals as (
        select * from public.signal_events
        where created_at >= p_day and created_at < p_day + 1
    ), day_pairs as (
        select connection_id, count(distinct sender_id) as senders
        from day_signals group by connection_id
    )
    insert into private.metrics_daily (
        day, accounts, new_accounts, accepted_invites, connections, signals, active_pairs,
        two_way_pairs, first_two_way_pairs, returning_pairs, push_failed, push_no_devices,
        blocks, reports, notifications_off, notifications_reported)
    select
        p_day,
        (select count(*) from public.profiles),
        (select count(*) from public.profiles where created_at >= p_day and created_at < p_day + 1),
        (select count(*) from public.invites where accepted_at >= p_day and accepted_at < p_day + 1),
        (select count(*) from public.connections),
        (select count(*) from day_signals),
        (select count(*) from day_pairs),
        (select count(*) from day_pairs where senders = 2),
        (select count(*) from public.connections where first_two_way_at >= p_day and first_two_way_at < p_day + 1),
        (select count(*) from day_pairs d join public.connections c on c.id = d.connection_id
         where d.senders = 2 and c.first_two_way_at < p_day),
        (select count(*) from day_signals where push_status = 'failed'),
        (select count(*) from day_signals where push_status = 'no_devices'),
        (select count(*) from public.blocks where created_at >= p_day and created_at < p_day + 1),
        (select count(*) from public.reports where created_at >= p_day and created_at < p_day + 1),
        (select count(*) from public.profiles where notifications_enabled = false),
        (select count(*) from public.profiles where notifications_enabled is not null)
    on conflict (day) do update set
        accounts = excluded.accounts, new_accounts = excluded.new_accounts,
        accepted_invites = excluded.accepted_invites, connections = excluded.connections,
        signals = excluded.signals, active_pairs = excluded.active_pairs,
        two_way_pairs = excluded.two_way_pairs, first_two_way_pairs = excluded.first_two_way_pairs,
        returning_pairs = excluded.returning_pairs, push_failed = excluded.push_failed,
        push_no_devices = excluded.push_no_devices, blocks = excluded.blocks, reports = excluded.reports,
        notifications_off = excluded.notifications_off,
        notifications_reported = excluded.notifications_reported, created_at = now();
$$;

revoke all on private.metrics_daily from public, anon, authenticated;
revoke execute on function public.set_notification_status(boolean), private.mark_first_two_way(),
    private.snapshot_metrics(date) from public, anon, authenticated;
grant execute on function public.set_notification_status(boolean) to authenticated;

-- Snapshot yesterday every night, after the day is complete (Supabase has pg_cron).
do $$
begin
    if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
        create extension if not exists pg_cron;
        execute $cron$
            select cron.schedule('psst-metrics', '10 0 * * *', 'select private.snapshot_metrics(current_date - 1)')
        $cron$;
    end if;
end;
$$;
