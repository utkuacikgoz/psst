-- Streak reminder when a freeze would save the streak (owner pick 3B on the 1.0.9
-- follow-ups page, 11 Nov 2026). Before: no reminder while a freeze would save it.
-- Now the reminder goes out anyway, with a line that stays true:
--   "Your 6-day streak with Mia needs a Psst today 🔥"  (a freeze would cover today)
--   "Your 6-day streak with Mia ends at midnight 🔥"     (nothing would save it)

create or replace function private.streak_reminder_targets_at(p_now timestamptz) returns jsonb
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

        select c.id, o.display_name as name, private.streak_days_on(c.id, today) as days,
               (s.last_day = today - 1 and private.pair_freezer(c.id, today) is not null) as frozen_ok into risk
        from public.connections c
        join private.pair_streaks s on s.connection_id = c.id
        join public.profiles o on o.id = case when c.user_a = p.id then c.user_b else c.user_a end
        where p.id in (c.user_a, c.user_b)
          and s.last_day < today
          and private.streak_days_on(c.id, today) >= 3
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
            'body', 'Your ' || risk.days || '-day streak with ' || risk.name
                    || case when risk.frozen_ok then ' needs a Psst today 🔥' else ' ends at midnight 🔥' end,
            'sound', p.notification_sound,
            'tokens', coalesce((select jsonb_agg(jsonb_build_object('token', t.token, 'environment', t.environment))
                                from public.device_tokens t where t.user_id = p.id), '[]'::jsonb)));
    end loop;
    return result;
end;
$$;

revoke execute on function private.streak_reminder_targets_at(timestamptz) from public, anon, authenticated;
