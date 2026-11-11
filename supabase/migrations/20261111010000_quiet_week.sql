-- Quiet-week push (owner pick 11A, 10 Nov 2026). Sundays at 6 PM on your own
-- clock, only with the weekly recap on (its switch turns this off too): after a
-- week (Monday to Sunday, your calendar) with no Pssts sent or received, if the
-- week before had some, one push: "Quiet week. Psst Kim?", Kim being last week's
-- #1 (recap_for's ranking). It opens Kim's band. At most once every three weeks;
-- skipped if Kim is no longer connected or either of you blocked the other.
-- The recap itself skips quiet weeks, so the two never both send.

create table private.quiet_week_state (
    user_id uuid primary key references public.profiles (id) on delete cascade,
    last_checked date,  -- the Sunday last looked at (one look per week)
    last_sent date      -- the Sunday of the last quiet-week push
);
revoke all on private.quiet_week_state from public, anon, authenticated;

create function private.quiet_week_targets_at(p_now timestamptz) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
    p record;
    week_end date;
    st private.quiet_week_state;
    this_week jsonb; last_week jsonb;
    top uuid; other uuid;
    result jsonb := '[]'::jsonb;
begin
    for p in
        select pr.id, pr.notification_sound
        from public.profiles pr
        where pr.weekly_recap
          and extract(isodow from (p_now at time zone coalesce(pr.time_zone, 'UTC'))) = 7
          and extract(hour from (p_now at time zone coalesce(pr.time_zone, 'UTC'))) >= 18
    loop
        week_end := private.local_day(p.id, p_now);
        select * into st from private.quiet_week_state where user_id = p.id;
        continue when st.last_checked >= week_end;

        -- The claim: one look per person per Sunday, even with two runs at once.
        insert into private.quiet_week_state as q (user_id, last_checked) values (p.id, week_end)
        on conflict (user_id) do update set last_checked = excluded.last_checked
            where q.last_checked is null or q.last_checked < excluded.last_checked;
        continue when not found;

        continue when st.last_sent > week_end - 21;
        this_week := private.recap_for(p.id, week_end);
        continue when (this_week ->> 'total')::int > 0;
        last_week := private.recap_for(p.id, week_end - 7);
        continue when (last_week ->> 'total')::int = 0;
        top := (last_week #>> '{top,connection_id}')::uuid;
        continue when top is null;

        select case when c.user_a = p.id then c.user_b else c.user_a end into other
        from public.connections c where c.id = top and p.id in (c.user_a, c.user_b);
        continue when other is null;
        continue when exists (select 1 from public.blocks b
                              where (b.blocker_id = p.id and b.blocked_id = other)
                                 or (b.blocker_id = other and b.blocked_id = p.id));

        update private.quiet_week_state set last_sent = week_end where user_id = p.id;
        result := result || jsonb_build_array(jsonb_build_object(
            'user_id', p.id,
            'connection_id', top,
            'body', 'Quiet week. Psst ' || (select display_name from public.profiles where id = other) || '?',
            'sound', p.notification_sound,
            'tokens', coalesce((select jsonb_agg(jsonb_build_object('token', t.token, 'environment', t.environment))
                                from public.device_tokens t where t.user_id = p.id), '[]'::jsonb)));
    end loop;
    return result;
end;
$$;

-- Server-only, for the hourly weekly-recap run.
create function public.quiet_week_targets() returns jsonb
language sql security definer set search_path = '' as $$
    select private.quiet_week_targets_at(now());
$$;

revoke execute on function private.quiet_week_targets_at(timestamptz), public.quiet_week_targets()
    from public, anon, authenticated;
grant execute on function public.quiet_week_targets() to service_role;
