-- "Same moment" (owner pick X2): when two connected people psst each other
-- within 10 seconds, by the server's clock, the second signal is marked and
-- both phones show SAME MOMENT: the second sender from the send result, the
-- first from the signal they receive. At most one per pair per minute, so a
-- rapid back-and-forth doesn't turn into a string of moments.

alter table public.signal_events add column same_moment boolean not null default false;

create function private.mark_same_moment() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
    new.same_moment := exists (
        select 1 from public.signal_events
        where connection_id = new.connection_id
          and sender_id = new.recipient_id and recipient_id = new.sender_id
          and created_at > new.created_at - interval '10 seconds'
    ) and not exists (
        select 1 from public.signal_events
        where connection_id = new.connection_id and same_moment
          and created_at > new.created_at - interval '1 minute'
    );
    return new;
end;
$$;

create trigger signal_events_same_moment
before insert on public.signal_events
for each row execute function private.mark_same_moment();

create or replace function public.send_signal(p_event_id uuid, p_connection_id uuid, p_effect_id text)
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

    -- Pacing: at most 10 per minute to one person and 30 per minute overall.
    if (select count(*) from public.signal_events
        where sender_id = me and recipient_id = other
          and created_at > now() - interval '1 minute') >= 10
       or (select count(*) from public.signal_events
           where sender_id = me and created_at > now() - interval '1 minute') >= 30 then
        raise exception 'rate_limited' using errcode = 'PT429';
    end if;

    insert into public.signal_events (id, connection_id, sender_id, recipient_id, effect_id)
    values (p_event_id, c.id, me, other, p_effect_id)
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

    return jsonb_build_object('id', ev.id, 'created_at', ev.created_at,
        'push_status', ev.push_status, 'duplicate', false,
        'same_moment', ev.same_moment);
end;
$$;

drop function public.list_unseen();
create function public.list_unseen() returns table (
    id uuid, connection_id uuid, sender_id uuid, sender_name text, effect_id text, created_at timestamptz,
    same_moment boolean
)
language plpgsql security definer set search_path = '' as $$
declare
    me uuid := private.require_user();
begin
    return query
    select s.id, s.connection_id, s.sender_id, p.display_name, s.effect_id, s.created_at, s.same_moment
    from public.signal_events s join public.profiles p on p.id = s.sender_id
    where s.recipient_id = me and s.seen_at is null
    order by s.created_at desc
    limit 50;
end;
$$;

create or replace function public.push_targets(p_event_id uuid) returns jsonb
language sql security definer set search_path = '' as $$
    select jsonb_build_object(
        'event_id', s.id,
        'connection_id', s.connection_id,
        'effect_id', s.effect_id,
        'same_moment', s.same_moment,
        'push_status', s.push_status,
        'sender_name', p.display_name,
        'tokens', coalesce((select jsonb_agg(jsonb_build_object('token', t.token, 'environment', t.environment))
                            from public.device_tokens t where t.user_id = s.recipient_id), '[]'::jsonb))
    from public.signal_events s join public.profiles p on p.id = s.sender_id
    where s.id = p_event_id;
$$;

revoke execute on function public.list_unseen(), private.mark_same_moment() from public, anon, authenticated;
grant execute on function public.list_unseen() to authenticated;
