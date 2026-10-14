-- Streaks (owner pick 3A, 14 Oct 2026). A day counts when you and they have each
-- pssted the other at least once that day, each by your own phone's calendar.
-- Kept per pair beyond the 30-day purge: a few dates and two numbers, no content.

-- The phone's time zone (IANA name), so "a day" is the person's own day.
-- Not readable by anyone else: profiles' select grant names its columns.
alter table public.profiles add column time_zone text;

create function public.set_time_zone(p_time_zone text) returns void
language plpgsql security definer set search_path = '' as $$
declare
    me uuid := private.require_user();
begin
    if p_time_zone is null or not exists (select 1 from pg_catalog.pg_timezone_names where name = p_time_zone) then
        raise exception 'invalid_time_zone' using errcode = 'PT400';
    end if;
    update public.profiles set time_zone = p_time_zone where id = me;
end;
$$;

create function private.local_day(p_user uuid, p_at timestamptz) returns date
language sql stable set search_path = '' as $$
    select (p_at at time zone coalesce((select time_zone from public.profiles where id = p_user), 'UTC'))::date;
$$;

create table private.pair_streaks (
    connection_id uuid primary key references public.connections (id) on delete cascade,
    a_last date,              -- user_a's latest own day with a Psst to user_b
    b_last date,              -- and the other way round
    last_day date,            -- the latest day both pssted
    current int not null default 0,
    longest int not null default 0
);
revoke all on private.pair_streaks from public, anon, authenticated;

create function private.track_streak(p_connection uuid, p_sender uuid, p_at timestamptz) returns void
language plpgsql security definer set search_path = '' as $$
declare
    c public.connections;
    d date := private.local_day(p_sender, p_at);
    s private.pair_streaks;
begin
    select * into c from public.connections where id = p_connection;
    if c.id is null then return; end if;
    insert into private.pair_streaks (connection_id) values (p_connection) on conflict do nothing;
    update private.pair_streaks set
        a_last = case when c.user_a = p_sender then greatest(coalesce(a_last, d), d) else a_last end,
        b_last = case when c.user_b = p_sender then greatest(coalesce(b_last, d), d) else b_last end
    where connection_id = p_connection
    returning * into s;
    -- Both have pssted on the same day, and it isn't counted yet.
    if s.a_last = s.b_last and (s.last_day is null or s.last_day < s.a_last) then
        update private.pair_streaks set
            current = case when s.last_day = s.a_last - 1 then s.current + 1 else 1 end,
            longest = greatest(s.longest, case when s.last_day = s.a_last - 1 then s.current + 1 else 1 end),
            last_day = s.a_last
        where connection_id = p_connection;
    end if;
end;
$$;

create function private.track_streak_signal() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
    perform private.track_streak(new.connection_id, new.sender_id, new.created_at);
    return null;
end;
$$;

create trigger signal_events_streak
    after insert on public.signal_events
    for each row execute function private.track_streak_signal();

-- Start from the Pssts still kept (the last 30 days), in order.
do $$
declare r record;
begin
    for r in select connection_id, sender_id, created_at from public.signal_events order by created_at, id loop
        perform private.track_streak(r.connection_id, r.sender_id, r.created_at);
    end loop;
end;
$$;

-- A streak is alive while its last day is today or yesterday, by the viewer's own day.
create function private.streak_days(p_connection uuid, p_viewer uuid) returns int
language sql stable security definer set search_path = '' as $$
    select coalesce((
        select s.current from private.pair_streaks s
        where s.connection_id = p_connection
          and s.last_day >= private.local_day(p_viewer, now()) - 1), 0);
$$;

-- list_connections gains streak_days (older apps ignore the extra column).
drop function public.list_connections();
create function public.list_connections() returns table (
    connection_id uuid,
    other_id uuid,
    other_name text,
    my_favorite text,
    last_event_id uuid,
    last_from_me boolean,
    last_effect text,
    last_created_at timestamptz,
    last_seen_at timestamptz,
    unseen_count int,
    streak_days int
)
language plpgsql security definer set search_path = '' as $$
declare
    me uuid := private.require_user();
begin
    return query
    select c.id,
           o.id,
           o.display_name,
           case when c.user_a = me then c.a_favorite else c.b_favorite end,
           e.id,
           e.sender_id = me,
           e.effect_id,
           e.created_at,
           e.seen_at,
           (select count(*)::int from public.signal_events u
            where u.connection_id = c.id and u.recipient_id = me and u.seen_at is null),
           private.streak_days(c.id, me)
    from public.connections c
    join public.profiles o on o.id = case when c.user_a = me then c.user_b else c.user_a end
    left join lateral (
        select * from public.signal_events s
        where s.connection_id = c.id
        order by s.created_at desc, s.id
        limit 1
    ) e on true
    where me in (c.user_a, c.user_b)
    order by o.display_name, c.id;
end;
$$;

revoke execute on function public.list_connections(), public.set_time_zone(text),
    private.local_day(uuid, timestamptz), private.track_streak(uuid, uuid, timestamptz),
    private.track_streak_signal(), private.streak_days(uuid, uuid) from public, anon, authenticated;
grant execute on function public.list_connections(), public.set_time_zone(text) to authenticated;
