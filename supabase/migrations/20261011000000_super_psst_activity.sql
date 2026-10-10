-- Personal activity, one daily Super Psst, verified Psst+ and recipient controls.
-- Daily reset is 00:00 UTC; clients render the returned time in local timezone.
insert into public.effects(id,title,is_free,sort_order) values ('super_psst','Super Psst',true,2);
alter table public.profiles add column super_effects_enabled boolean not null default true;

-- A quota survives deleting an individual connection or its retained signal events.
create table private.super_usage (
    user_id uuid not null references public.profiles(id) on delete cascade,
    day date not null,
    primary key(user_id, day)
);
create table private.plus_entitlements (
    user_id uuid primary key references public.profiles(id) on delete cascade,
    original_transaction_id text not null unique,
    valid_until timestamptz not null
);
revoke all on private.super_usage, private.plus_entitlements from public, anon, authenticated;

-- Called ONLY by the verification edge function after Apple's signature and
-- current transaction status are checked. A purchase cannot serve two accounts.
create function public.record_verified_plus(p_user_id uuid, p_original_id text, p_active boolean)
returns void language plpgsql security definer set search_path = '' as $$
begin
    if exists(select 1 from private.plus_entitlements where original_transaction_id = p_original_id and user_id <> p_user_id) then
        raise exception 'purchase_already_linked' using errcode = 'PT409';
    end if;
    insert into private.plus_entitlements(user_id, original_transaction_id, valid_until)
    values(p_user_id, p_original_id, case when p_active then now() + interval '5 minutes' else now() end)
    on conflict(user_id) do update set
        original_transaction_id = excluded.original_transaction_id, valid_until = excluded.valid_until;
end;
$$;
revoke execute on function public.record_verified_plus(uuid,text,boolean) from public, anon, authenticated;
grant execute on function public.record_verified_plus(uuid,text,boolean) to service_role;

create function public.super_allowance() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare me uuid := private.require_user();
begin
    return jsonb_build_object(
        'remaining', case when exists(select 1 from private.super_usage where user_id = me and day = (now() at time zone 'UTC')::date) then 0 else 1 end,
        'unlimited', exists(select 1 from private.plus_entitlements where user_id = me and valid_until > now()),
        'resets_at', (((now() at time zone 'UTC')::date + 1)::timestamp at time zone 'UTC'),
        'effects_enabled', coalesce((select super_effects_enabled from public.profiles where id = me), true));
end;
$$;
create function public.set_super_effects(p_enabled boolean) returns void
language plpgsql security definer set search_path = '' as $$
declare me uuid := private.require_user();
begin
    if p_enabled is null then raise exception 'invalid_preference' using errcode = 'PT422'; end if;
    update public.profiles set super_effects_enabled = p_enabled where id = me;
    if not found then raise exception 'profile_required' using errcode = 'PT409'; end if;
end;
$$;

create function public.personal_activity() returns table (
    connection_id uuid, other_name text, sent_count bigint, received_count bigint
) language plpgsql security definer set search_path = '' as $$
declare me uuid := private.require_user();
begin
    return query
    select c.id, p.display_name,
           count(s.id) filter(where s.sender_id = me),
           count(s.id) filter(where s.recipient_id = me)
    from public.connections c
    join public.profiles p on p.id = case when c.user_a = me then c.user_b else c.user_a end
    left join public.signal_events s on s.connection_id = c.id and s.created_at >= now() - interval '30 days'
    where me in(c.user_a,c.user_b) and not private.is_blocked(me,p.id)
    group by c.id,p.display_name;
end;
$$;

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

    if p_effect_id = 'super_psst' then
        insert into private.super_usage(user_id, day)
        values (me, (now() at time zone 'UTC')::date) on conflict do nothing;
    end if;

    return jsonb_build_object('id', ev.id, 'created_at', ev.created_at,
        'push_status', ev.push_status, 'duplicate', false,
        'same_moment', ev.same_moment);
end;
$$;


drop function public.list_unseen();
create function public.list_unseen() returns table (
    id uuid, connection_id uuid, sender_id uuid, sender_name text, effect_id text,
    created_at timestamptz, same_moment boolean
) language plpgsql security definer set search_path = '' as $$
declare me uuid := private.require_user();
begin
    return query
    select s.id,s.connection_id,s.sender_id,p.display_name,
           case when s.effect_id = 'super_psst' and not r.super_effects_enabled then 'psst' else s.effect_id end,
           s.created_at,s.same_moment
    from public.signal_events s
    join public.profiles p on p.id = s.sender_id
    join public.profiles r on r.id = s.recipient_id
    where s.recipient_id = me and s.seen_at is null
    order by s.created_at desc limit 50;
end;
$$;

create or replace function public.push_targets(p_event_id uuid) returns jsonb
language sql security definer set search_path = '' as $$
    select jsonb_build_object(
        'event_id',s.id,'connection_id',s.connection_id,
        'effect_id',case when s.effect_id = 'super_psst' and not r.super_effects_enabled then 'psst' else s.effect_id end,
        'same_moment',s.same_moment,
        'sound',case when s.effect_id = 'super_psst' and r.super_effects_enabled then 'psst-super.wav' else r.notification_sound end,
        'push_status',s.push_status,'sender_name',p.display_name,
        'tokens',coalesce((select jsonb_agg(jsonb_build_object('token',t.token,'environment',t.environment))
                          from public.device_tokens t where t.user_id = s.recipient_id),'[]'::jsonb))
    from public.signal_events s
    join public.profiles p on p.id = s.sender_id
    join public.profiles r on r.id = s.recipient_id where s.id = p_event_id;
$$;
revoke execute on function public.super_allowance(), public.set_super_effects(boolean), public.personal_activity(), public.list_unseen() from public,anon,authenticated;
grant execute on function public.super_allowance(), public.set_super_effects(boolean), public.personal_activity(), public.list_unseen() to authenticated;

-- Keep quota bookkeeping within the same 30-day retention window as activity.
create or replace function private.purge_expired() returns void
language sql security definer set search_path = '' as $$
    delete from public.signal_events where created_at < now() - interval '30 days';
    delete from public.invites where coalesce(accepted_at, revoked_at, expires_at) < now() - interval '30 days';
    delete from private.super_usage where day < (now() at time zone 'UTC')::date - 30;
$$;
