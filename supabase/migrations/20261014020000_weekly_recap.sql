-- Weekly recap (owner pick 4A, 14 Oct 2026): off until you turn it on. Sundays at
-- 6 PM on your phone's clock, covering Monday to Sunday. Weeks with no Pssts are
-- skipped. Only you see it.

alter table public.profiles add column weekly_recap boolean not null default false;

-- What the last recap said, to tell "still your #1" from "your new #1".
create table private.recap_state (
    user_id uuid primary key references public.profiles (id) on delete cascade,
    last_week date,     -- the Sunday of the last recap sent
    last_top uuid,      -- its #1 (connection)
    prev_top uuid       -- the #1 of the recap before that
);
revoke all on private.recap_state from public, anon, authenticated;

-- The Sunday ending the week to show: today if it's Sunday, else the last one.
create function private.recap_week_end(p_user uuid) returns date
language sql stable set search_path = '' as $$
    select d - (extract(isodow from d)::int % 7)
    from (select private.local_day(p_user, now()) as d) t;
$$;

-- One person's week, Monday to Sunday by their own calendar.
create function private.recap_for(p_user uuid, p_week_end date) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
    zone text := coalesce((select time_zone from public.profiles where id = p_user), 'UTC');
    sent int; received int;
    top record; streak record; st private.recap_state;
    still boolean;
begin
    select count(*) filter (where s.sender_id = p_user), count(*) filter (where s.recipient_id = p_user)
    into sent, received
    from public.signal_events s
    where p_user in (s.sender_id, s.recipient_id)
      and (s.created_at at time zone zone)::date between p_week_end - 6 and p_week_end;

    select c.id, o.display_name as name, count(*)::int as n into top
    from public.signal_events s
    join public.connections c on c.id = s.connection_id
    join public.profiles o on o.id = case when c.user_a = p_user then c.user_b else c.user_a end
    where p_user in (c.user_a, c.user_b)
      and (s.created_at at time zone zone)::date between p_week_end - 6 and p_week_end
    group by c.id, o.display_name
    order by count(*) desc, o.display_name
    limit 1;

    select c.id, o.display_name as name, private.streak_days(c.id, p_user) as days into streak
    from public.connections c
    join public.profiles o on o.id = case when c.user_a = p_user then c.user_b else c.user_a end
    where p_user in (c.user_a, c.user_b) and private.streak_days(c.id, p_user) >= 3
    order by private.streak_days(c.id, p_user) desc, o.display_name
    limit 1;

    select * into st from private.recap_state where user_id = p_user;
    -- Compare with the recap before this week's one.
    still := case when st.last_week = p_week_end then st.prev_top = top.id else st.last_top = top.id end;

    return jsonb_build_object(
        'week_start', p_week_end - 6, 'week_end', p_week_end,
        'total', sent + received, 'sent', sent, 'received', received,
        'top', case when top.id is null then null else jsonb_build_object(
            'connection_id', top.id, 'name', top.name, 'count', top.n, 'still', coalesce(still, false)) end,
        'streak', case when streak.id is null then null else jsonb_build_object(
            'connection_id', streak.id, 'name', streak.name, 'days', streak.days) end);
end;
$$;

create function public.weekly_recap() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
    me uuid := private.require_user();
begin
    return private.recap_for(me, private.recap_week_end(me));
end;
$$;

-- Whether it's on, and this week's total so far (the offer shows after a busy week).
create function public.weekly_recap_status() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
    me uuid := private.require_user();
    week jsonb := private.recap_for(me, private.local_day(me, now()) + (7 - extract(isodow from private.local_day(me, now()))::int));
begin
    return jsonb_build_object(
        'enabled', coalesce((select weekly_recap from public.profiles where id = me), false),
        'week_total', (week ->> 'total')::int);
end;
$$;

create function public.set_weekly_recap(p_enabled boolean) returns void
language plpgsql security definer set search_path = '' as $$
declare
    me uuid := private.require_user();
begin
    update public.profiles set weekly_recap = coalesce(p_enabled, false) where id = me;
end;
$$;

-- Server-only: everyone whose Sunday 6 PM has come and who hasn't had this week's
-- recap. Marks it sent as it goes, so a second run in the same hour sends nothing.
create function public.recap_push_targets() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
    p record;
    week_end date;
    recap jsonb;
    title text; body text;
    result jsonb := '[]'::jsonb;
begin
    for p in
        select pr.id, pr.notification_sound
        from public.profiles pr
        where pr.weekly_recap
          and extract(isodow from (now() at time zone coalesce(pr.time_zone, 'UTC'))) = 7
          and extract(hour from (now() at time zone coalesce(pr.time_zone, 'UTC'))) >= 18
    loop
        week_end := private.local_day(p.id, now());
        if exists (select 1 from private.recap_state where user_id = p.id and last_week >= week_end) then
            continue;
        end if;
        recap := private.recap_for(p.id, week_end);
        insert into private.recap_state as rs (user_id, last_week, last_top, prev_top)
        values (p.id, week_end, (recap #>> '{top,connection_id}')::uuid, null)
        on conflict (user_id) do update set
            prev_top = rs.last_top, last_top = excluded.last_top, last_week = excluded.last_week;
        continue when (recap ->> 'total')::int = 0;

        title := 'Your week: ' || (recap ->> 'total') || ' Pssts';
        body := (recap #>> '{top,name}') || case
            when (recap #>> '{top,still}')::boolean then ' is still your #1.'
            when exists (select 1 from private.recap_state where user_id = p.id and prev_top is not null) then ' is your new #1.'
            else ' is your #1.' end;
        if recap -> 'streak' <> 'null'::jsonb then
            body := body || ' You and ' || (recap #>> '{streak,name}') || ' are on a '
                || (recap #>> '{streak,days}') || '-day streak.';
        end if;
        result := result || jsonb_build_array(jsonb_build_object(
            'user_id', p.id, 'title', title, 'body', body, 'sound', p.notification_sound,
            'tokens', coalesce((select jsonb_agg(jsonb_build_object('token', t.token, 'environment', t.environment))
                                from public.device_tokens t where t.user_id = p.id), '[]'::jsonb)));
    end loop;
    return result;
end;
$$;

-- The hourly job: pg_cron calls the weekly-recap function through pg_net, with a
-- secret that lives only in the database's vault (never in the repo).
create function public.recap_cron_ok(p_secret text) returns boolean
language plpgsql security definer set search_path = '' as $$
declare ok boolean := false;
begin
    if to_regclass('vault.decrypted_secrets') is null or p_secret is null then return false; end if;
    execute 'select exists (select 1 from vault.decrypted_secrets where name = $1 and decrypted_secret = $2)'
        into ok using 'psst_recap_cron', p_secret;
    return ok;
end;
$$;

-- Called once by the deploy with the function's URL.
create function public.schedule_weekly_recap(p_url text) returns void
language plpgsql security definer set search_path = '' as $$
begin
    if to_regclass('vault.decrypted_secrets') is null
       or to_regnamespace('cron') is null or to_regnamespace('net') is null then
        raise exception 'scheduler_unavailable' using errcode = 'PT503';
    end if;
    if not exists (select 1 from vault.decrypted_secrets where name = 'psst_recap_cron') then
        perform vault.create_secret(replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''), 'psst_recap_cron');
    end if;
    perform cron.schedule('psst-weekly-recap', '7 * * * *', format(
        $job$select net.http_post(url := %L, body := '{}'::jsonb, headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'psst_recap_cron')))$job$,
        p_url));
end;
$$;

do $$
begin
    if exists (select 1 from pg_available_extensions where name = 'pg_net') then
        create extension if not exists pg_net;
    end if;
end;
$$;

revoke execute on function private.recap_week_end(uuid), private.recap_for(uuid, date),
    public.weekly_recap(), public.weekly_recap_status(), public.set_weekly_recap(boolean),
    public.recap_push_targets(), public.recap_cron_ok(text), public.schedule_weekly_recap(text)
    from public, anon, authenticated;
grant execute on function public.weekly_recap(), public.weekly_recap_status(), public.set_weekly_recap(boolean)
    to authenticated;
grant execute on function public.recap_push_targets(), public.recap_cron_ok(text), public.schedule_weekly_recap(text)
    to service_role;
