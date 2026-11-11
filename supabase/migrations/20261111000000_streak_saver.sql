-- Streak saver (owner pick 5A, 10 Nov 2026). Opt-in: off by default, so the
-- 3A rule (no streak notifications) stays the default.
--
-- With it on:
-- * Reminder: at 8 PM on your own clock, if one of your streaks (3+ days) ends at
--   midnight because today isn't kept yet, one push: "Your 6-day streak with Mia
--   ends at midnight 🔥". Never more than one a day per account (the longest
--   streak at risk). No reminder when a freeze would save it anyway (the copy
--   would be untrue).
-- * Freeze: one missed day per calendar month is forgiven, so the streak goes on;
--   Psst+ (an active plus_entitlement) has unlimited freezes.
--
-- The rules, kept simple:
-- * A freeze covers ONE missed day between two kept days. Two missed days in a
--   row end any streak, Psst+ included.
-- * The frozen day doesn't add to the count: kept 5 days, missed one, kept the
--   next = a 6-day streak.
-- * A streak belongs to two people; a freeze from either of them (with the saver
--   on) saves it, spent from one account only: a Psst+ member first (costs
--   nothing), else user_a's monthly freeze, else user_b's.
-- * The month is the missed day's month (days are each person's own calendar,
--   as for streaks).
-- * A freeze is claimed when the streak goes on (the next kept day). Until then
--   streak_days already shows the streak as alive if a freeze is available, so
--   list_connections, the widget and the recap agree. If two of your streaks
--   wait on your one free freeze, the first to go on gets it.

alter table public.profiles add column streak_reminders boolean not null default false;

-- Freezes spent. plus = spent while Psst+ (doesn't use up the monthly one).
create table private.streak_freezes (
    connection_id uuid not null references public.connections (id) on delete cascade,
    day date not null,      -- the missed day it covered
    user_id uuid not null references public.profiles (id) on delete cascade,
    plus boolean not null,
    created_at timestamptz not null default now(),
    primary key (connection_id, day)
);
create index streak_freezes_user_idx on private.streak_freezes (user_id, day);
revoke all on private.streak_freezes from public, anon, authenticated;

-- Server-side once-a-day guard for the reminder.
create table private.streak_reminder_state (
    user_id uuid primary key references public.profiles (id) on delete cascade,
    last_day date not null  -- the local day of the last reminder
);
revoke all on private.streak_reminder_state from public, anon, authenticated;

create function private.has_plus(p_user uuid) returns boolean
language sql stable security definer set search_path = '' as $$
    select exists (select 1 from private.plus_entitlements where user_id = p_user and valid_until > now());
$$;

-- Whether this person could freeze a missed day: saver on, and Psst+ or this
-- month's free freeze unused.
create function private.can_freeze(p_user uuid, p_day date) returns boolean
language sql stable security definer set search_path = '' as $$
    select coalesce((select streak_reminders from public.profiles where id = p_user), false)
       and (private.has_plus(p_user) or not exists (
            select 1 from private.streak_freezes f
            where f.user_id = p_user and not f.plus
              and f.day >= date_trunc('month', p_day)::date
              and f.day < (date_trunc('month', p_day) + interval '1 month')::date));
$$;

-- Who would spend the freeze for this pair's missed day (null: nobody can).
create function private.pair_freezer(p_connection uuid, p_day date) returns uuid
language sql stable security definer set search_path = '' as $$
    select u.id
    from public.connections c
    cross join lateral (values (c.user_a, 1), (c.user_b, 2)) u(id, ord)
    where c.id = p_connection and private.can_freeze(u.id, p_day)
    order by private.has_plus(u.id) desc, u.ord
    limit 1;
$$;

-- The streak as seen on p_today (the viewer's day). Alive while its last kept
-- day is today or yesterday, or the day before yesterday with a freeze ready
-- for yesterday.
create function private.streak_days_on(p_connection uuid, p_today date) returns int
language sql stable security definer set search_path = '' as $$
    select coalesce((
        select s.current from private.pair_streaks s
        where s.connection_id = p_connection
          and (s.last_day >= p_today - 1
               or (s.last_day = p_today - 2 and private.pair_freezer(p_connection, p_today - 1) is not null))), 0);
$$;

-- Same signature as before: list_connections, widget_state and the recap use it.
create or replace function private.streak_days(p_connection uuid, p_viewer uuid) returns int
language sql stable security definer set search_path = '' as $$
    select private.streak_days_on(p_connection, private.local_day(p_viewer, now()));
$$;

-- Spends a freeze for the pair's missed day; false if nobody could. Locks both
-- people (in a fixed order) so one free freeze can't be spent twice at once.
create function private.claim_streak_freeze(p_connection uuid, p_day date) returns boolean
language plpgsql security definer set search_path = '' as $$
declare
    c public.connections;
    who uuid;
begin
    select * into c from public.connections where id = p_connection;
    if c.id is null then return false; end if;
    perform pg_advisory_xact_lock(hashtextextended('psst_streak_freeze:' || least(c.user_a, c.user_b)::text, 0));
    perform pg_advisory_xact_lock(hashtextextended('psst_streak_freeze:' || greatest(c.user_a, c.user_b)::text, 0));
    if exists (select 1 from private.streak_freezes where connection_id = p_connection and day = p_day) then
        return true;
    end if;
    who := private.pair_freezer(p_connection, p_day);
    if who is null then return false; end if;
    insert into private.streak_freezes (connection_id, day, user_id, plus)
    values (p_connection, p_day, who, private.has_plus(who));
    return true;
end;
$$;

-- As before, plus: a kept day after exactly one missed day goes on if a freeze
-- covers the missed one.
create or replace function private.track_streak(p_connection uuid, p_sender uuid, p_at timestamptz) returns void
language plpgsql security definer set search_path = '' as $$
declare
    c public.connections;
    d date := private.local_day(p_sender, p_at);
    s private.pair_streaks;
    goes_on boolean;
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
        goes_on := s.last_day = s.a_last - 1
            or (s.last_day = s.a_last - 2 and s.current > 0
                and private.claim_streak_freeze(p_connection, s.a_last - 1));
        update private.pair_streaks set
            current = case when goes_on then s.current + 1 else 1 end,
            longest = greatest(s.longest, case when goes_on then s.current + 1 else 1 end),
            last_day = s.a_last
        where connection_id = p_connection;
    end if;
end;
$$;

create function public.set_streak_reminders(p_enabled boolean) returns void
language plpgsql security definer set search_path = '' as $$
declare me uuid := private.require_user();
begin
    if p_enabled is null then raise exception 'invalid_preference' using errcode = 'PT422'; end if;
    update public.profiles set streak_reminders = p_enabled where id = me;
    if not found then raise exception 'profile_required' using errcode = 'PT409'; end if;
end;
$$;

-- {"enabled", "unlimited" (active Psst+), "freezes_left" (this calendar month by
-- your own calendar: 0 or 1; 1 when unlimited, which the app ignores)}.
create function public.streak_saver_status() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
    me uuid := private.require_user();
    today date := private.local_day(me, now());
    plus boolean := private.has_plus(me);
begin
    return jsonb_build_object(
        'enabled', coalesce((select streak_reminders from public.profiles where id = me), false),
        'unlimited', plus,
        'freezes_left', case when plus or not exists (
            select 1 from private.streak_freezes f
            where f.user_id = me and not f.plus
              and f.day >= date_trunc('month', today)::date
              and f.day < (date_trunc('month', today) + interval '1 month')::date) then 1 else 0 end);
end;
$$;

-- Who gets the 8 PM reminder at p_now: saver on, 8 PM or later on their clock,
-- not reminded today, and a 3+ day streak that ends at their midnight (last kept
-- day before today, and no freeze would cover today). Claims the day as it goes,
-- so a second run (or two at once) sends nothing more.
create function private.streak_reminder_targets_at(p_now timestamptz) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
    p record;
    today date;
    risk record;
    result jsonb := '[]'::jsonb;
begin
    for p in
        select pr.id, pr.notification_sound
        from public.profiles pr
        where pr.streak_reminders
          and extract(hour from (p_now at time zone coalesce(pr.time_zone, 'UTC'))) >= 20
    loop
        today := private.local_day(p.id, p_now);
        continue when exists (select 1 from private.streak_reminder_state where user_id = p.id and last_day >= today);

        select c.id, o.display_name as name, private.streak_days_on(c.id, today) as days into risk
        from public.connections c
        join private.pair_streaks s on s.connection_id = c.id
        join public.profiles o on o.id = case when c.user_a = p.id then c.user_b else c.user_a end
        where p.id in (c.user_a, c.user_b)
          and s.last_day < today
          and private.streak_days_on(c.id, today) >= 3
          and not (s.last_day = today - 1 and private.pair_freezer(c.id, today) is not null)
          and not exists (select 1 from public.blocks b
                          where (b.blocker_id = p.id and b.blocked_id = o.id)
                             or (b.blocker_id = o.id and b.blocked_id = p.id))
        order by 3 desc, o.display_name, c.id
        limit 1;
        continue when risk.id is null;

        -- The claim: only one run gets past this per person per day.
        insert into private.streak_reminder_state as st (user_id, last_day) values (p.id, today)
        on conflict (user_id) do update set last_day = excluded.last_day where st.last_day < excluded.last_day;
        continue when not found;

        result := result || jsonb_build_array(jsonb_build_object(
            'user_id', p.id,
            'connection_id', risk.id,
            'body', 'Your ' || risk.days || '-day streak with ' || risk.name || ' ends at midnight 🔥',
            'sound', p.notification_sound,
            'tokens', coalesce((select jsonb_agg(jsonb_build_object('token', t.token, 'environment', t.environment))
                                from public.device_tokens t where t.user_id = p.id), '[]'::jsonb)));
    end loop;
    return result;
end;
$$;

-- Server-only, for the hourly weekly-recap run.
create function public.streak_reminder_targets() returns jsonb
language sql security definer set search_path = '' as $$
    select private.streak_reminder_targets_at(now());
$$;

revoke execute on function private.has_plus(uuid), private.can_freeze(uuid, date),
    private.pair_freezer(uuid, date), private.streak_days_on(uuid, date),
    private.claim_streak_freeze(uuid, date), private.streak_reminder_targets_at(timestamptz),
    public.set_streak_reminders(boolean), public.streak_saver_status(), public.streak_reminder_targets()
    from public, anon, authenticated;
revoke execute on function private.streak_days(uuid, uuid), private.track_streak(uuid, uuid, timestamptz)
    from public, anon, authenticated;
grant execute on function public.set_streak_reminders(boolean), public.streak_saver_status() to authenticated;
grant execute on function public.streak_reminder_targets() to service_role;
