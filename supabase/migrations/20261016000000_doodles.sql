-- Doodles (owner picks 1A 2A 3B 4A 5A, 15 Oct 2026): hold a band, draw with one
-- finger, and it lands on their widget as a polaroid and in a notification
-- ("Mia drew you something"). It stays there until they psst you back. Free.
-- A doodle is a signal with effect 'doodle' that carries its strokes: points
-- 0..1 in a square, at most 60 strokes and 2,000 points. Like every signal, it
-- is deleted after 30 days. Reporting the sender (hold a band) covers doodles.

insert into public.effects (id, title, is_free, sort_order) values ('doodle', 'Doodle', true, 3)
on conflict (id) do nothing;

alter table public.signal_events add column doodle jsonb;
alter table public.signal_events add constraint signal_events_doodle_size
    check (doodle is null or octet_length(doodle::text) <= 24000);

-- [[[x, y], [x, y], ...], ...] with every x, y a number from 0 to 1.
create function private.valid_doodle(p jsonb) returns boolean
language sql immutable set search_path = '' as $$
    select p is not null and jsonb_typeof(p) = 'array'
       and jsonb_array_length(p) between 1 and 60
       and octet_length(p::text) <= 24000
       and not exists (select 1 from jsonb_array_elements(p) s
                       where jsonb_typeof(s) <> 'array' or jsonb_array_length(s) = 0)
       and (select count(*) from jsonb_array_elements(p) s, jsonb_array_elements(s) pt) <= 2000
       and not exists (
           select 1 from jsonb_array_elements(p) s, jsonb_array_elements(s) pt
           where jsonb_typeof(pt) <> 'array' or jsonb_array_length(pt) <> 2
              or jsonb_typeof(pt -> 0) <> 'number' or jsonb_typeof(pt -> 1) <> 'number'
              or (pt ->> 0)::numeric not between 0 and 1 or (pt ->> 1)::numeric not between 0 and 1);
$$;

drop function public.send_signal(uuid, uuid, text);
create function public.send_signal(p_event_id uuid, p_connection_id uuid, p_effect_id text, p_doodle jsonb default null)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
    me uuid := private.require_user();
    c public.connections;
    other uuid;
    ev public.signal_events;
begin
    if p_event_id is null then
        raise exception 'invalid_event_id' using errcode = 'PT422';
    end if;

    -- Serialize all sends from this account: concurrent daily/pacing checks are atomic.
    perform pg_advisory_xact_lock(hashtextextended(me::text, 61011));

    -- Idempotent retry: the same ID from the same sender returns the original.
    select * into ev from public.signal_events where id = p_event_id;
    if found then
        if ev.sender_id <> me then
            raise exception 'invalid_event_id' using errcode = 'PT422';
        end if;
        return jsonb_build_object('id', ev.id, 'created_at', ev.created_at,
            'push_status', ev.push_status, 'duplicate', true,
            'same_moment', ev.same_moment);
    end if;

    select * into c from public.connections where id = p_connection_id and me in (user_a, user_b);
    if not found then
        raise exception 'not_connected' using errcode = 'PT403';
    end if;
    other := case when c.user_a = me then c.user_b else c.user_a end;
    if private.is_blocked(me, other) then
        raise exception 'not_connected' using errcode = 'PT403';
    end if;

    if not exists (select 1 from public.effects where id = p_effect_id and is_free) then
        raise exception 'effect_unavailable' using errcode = 'PT403';
    end if;

    -- A doodle carries its drawing; nothing else carries anything.
    if p_effect_id = 'doodle' then
        if not private.valid_doodle(p_doodle) then
            raise exception 'invalid_doodle' using errcode = 'PT422';
        end if;
    elsif p_doodle is not null then
        raise exception 'invalid_doodle' using errcode = 'PT422';
    end if;

    if p_effect_id = 'super_psst'
       and not exists (select 1 from private.plus_entitlements where user_id = me and valid_until > now())
       and exists (select 1 from private.super_usage where user_id = me
                   and day = (now() at time zone 'UTC')::date) then
        raise exception 'super_daily_limit' using errcode = 'PT409';
    end if;

    -- Pacing: at most 10 per minute to one person and 30 per minute overall.
    if (select count(*) from public.signal_events
        where sender_id = me and recipient_id = other
          and created_at > now() - interval '1 minute') >= 10
       or (select count(*) from public.signal_events
           where sender_id = me and created_at > now() - interval '1 minute') >= 30 then
        raise exception 'rate_limited' using errcode = 'PT429';
    end if;

    insert into public.signal_events (id, connection_id, sender_id, recipient_id, effect_id, doodle)
    values (p_event_id, c.id, me, other, p_effect_id, p_doodle)
    on conflict (id) do nothing
    returning * into ev;

    if ev.id is null then
        -- A concurrent request with the same ID won the insert.
        select * into ev from public.signal_events where id = p_event_id;
        if ev.sender_id <> me then
            raise exception 'invalid_event_id' using errcode = 'PT422';
        end if;
        return jsonb_build_object('id', ev.id, 'created_at', ev.created_at,
            'push_status', ev.push_status, 'duplicate', true,
            'same_moment', ev.same_moment);
    end if;

    if p_effect_id = 'super_psst' then
        insert into private.super_usage(user_id, day)
        values (me, (now() at time zone 'UTC')::date) on conflict do nothing;
    end if;

    return jsonb_build_object('id', ev.id, 'created_at', ev.created_at,
        'push_status', ev.push_status, 'duplicate', false,
        'same_moment', ev.same_moment);
end;
$$;

revoke execute on function public.send_signal(uuid, uuid, text, jsonb) from public, anon;
grant execute on function public.send_signal(uuid, uuid, text, jsonb) to authenticated;

-- Unseen signals now include a doodle's strokes.
drop function public.list_unseen();
create function public.list_unseen() returns table (
    id uuid, connection_id uuid, sender_id uuid, sender_name text, effect_id text,
    created_at timestamptz, same_moment boolean, doodle jsonb
) language plpgsql security definer set search_path = '' as $$
declare me uuid := private.require_user();
begin
    return query
    select s.id,s.connection_id,s.sender_id,p.display_name,
           case when s.effect_id = 'super_psst' and not r.super_effects_enabled then 'psst' else s.effect_id end,
           s.created_at,s.same_moment,s.doodle
    from public.signal_events s
    join public.profiles p on p.id = s.sender_id
    join public.profiles r on r.id = s.recipient_id
    where s.recipient_id = me and s.seen_at is null
    order by s.created_at desc limit 50;
end;
$$;
revoke execute on function public.list_unseen() from public, anon;
grant execute on function public.list_unseen() to authenticated;

-- What the widget shows: the newest doodle sent to you that you haven't answered
-- (no signal from you to that person since), while you're still connected.
create function public.latest_doodle() returns jsonb
language sql stable security definer set search_path = '' as $$
    select jsonb_build_object('event_id', s.id, 'connection_id', s.connection_id,
                              'sender_name', p.display_name, 'created_at', s.created_at, 'doodle', s.doodle)
    from public.signal_events s
    join public.profiles p on p.id = s.sender_id
    where s.recipient_id = private.require_user() and s.effect_id = 'doodle' and s.doodle is not null
      and exists (select 1 from public.connections c where c.id = s.connection_id)
      and not private.is_blocked(s.recipient_id, s.sender_id)
      and not exists (select 1 from public.signal_events r
                      where r.connection_id = s.connection_id and r.sender_id = s.recipient_id
                        and r.created_at > s.created_at)
    order by s.created_at desc
    limit 1;
$$;
revoke execute on function public.latest_doodle() from public, anon;
grant execute on function public.latest_doodle() to authenticated;
