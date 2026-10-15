-- Weekly recap on from the start (owner pick 2A, 16 Oct 2026; was opt-in, pick 4A).
-- New accounts start with it on, and everyone is switched on once; Settings ›
-- Weekly recap turns it off. It still only sends on Sundays at 6 PM in weeks
-- with Pssts, and iOS's notification permission still applies. 1.0.4 has no recap
-- and no switch for it, so only phones on 1.0.5 or later (build 26+) get one.

alter table public.profiles alter column weekly_recap set default true;
update public.profiles set weekly_recap = true where not weekly_recap;

-- Same as before, plus the build check, and "1 Psst" for a one-Psst week (4A).
create or replace function public.recap_push_targets() returns jsonb
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
          -- Only apps that have the recap and its off switch (1.0.5 is build 26 and later).
          and coalesce(pr.app_build, 0) >= 26
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

        title := 'Your week: ' || (recap ->> 'total') || case when (recap ->> 'total')::int = 1 then ' Psst' else ' Pssts' end;
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
