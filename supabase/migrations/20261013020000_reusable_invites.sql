-- Reusable invites (owner pick, 13 Oct 2026): a code joins up to 10 people
-- within its 7 days, so it can go to a group chat or a Story. Each join is a
-- separate, mutual connection, exactly as before. Codes made before this keep
-- working once (max_uses 1).

alter table public.invites
    add column max_uses int not null default 1,
    add column uses int not null default 0;
update public.invites set uses = 1 where accepted_at is not null;
alter table public.invites alter column max_uses set default 10;
alter table public.invites add constraint invites_uses_within_max check (uses between 0 and max_uses);

-- Who joined with which code. accepted_by / accepted_at on invites now hold the
-- latest join; this keeps every one (the inviter's "Kim is in" and metrics).
create table private.invite_uses (
    invite_id uuid not null references public.invites (id) on delete cascade,
    user_id uuid not null references public.profiles (id) on delete cascade,
    accepted_at timestamptz not null default now(),
    primary key (invite_id, user_id)
);
create index invite_uses_user_idx on private.invite_uses (user_id);
insert into private.invite_uses (invite_id, user_id, accepted_at)
select id, accepted_by, accepted_at from public.invites where accepted_by is not null;
revoke all on private.invite_uses from public, anon, authenticated;

create or replace function private.invite_status(inv public.invites, me uuid) returns text
language plpgsql stable set search_path = '' as $$
begin
    if inv.id is null then return 'invalid'; end if;
    if inv.inviter_id = me then return 'own'; end if;
    if private.is_blocked(me, inv.inviter_id) then return 'invalid'; end if;
    if exists (select 1 from public.connections
               where user_a = least(me, inv.inviter_id) and user_b = greatest(me, inv.inviter_id)) then
        return 'already_connected';
    end if;
    if inv.uses >= inv.max_uses then return 'used'; end if;
    if inv.revoked_at is not null then return 'revoked'; end if;
    if inv.expires_at <= now() then return 'expired'; end if;
    return 'pending';
end;
$$;

create or replace function public.accept_invite(p_code text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
    me uuid := private.require_user();
    inv public.invites;
    status text;
    conn_id uuid;
begin
    if not exists (select 1 from public.profiles where id = me) then
        raise exception 'profile_required' using errcode = 'PT409';
    end if;
    -- The row lock makes concurrent joins on one code take turns, so uses never passes max_uses.
    select * into inv from public.invites where code = private.normalize_code(p_code) for update;
    status := private.invite_status(inv, me);

    if status = 'pending' then
        insert into public.connections (user_a, user_b)
        values (least(me, inv.inviter_id), greatest(me, inv.inviter_id))
        returning id into conn_id;
        update public.invites set uses = uses + 1, accepted_by = me, accepted_at = now() where id = inv.id;
        insert into private.invite_uses (invite_id, user_id) values (inv.id, me)
        on conflict (invite_id, user_id) do update set accepted_at = now();
        status := 'accepted';
    elsif status = 'already_connected' then
        select id into conn_id from public.connections
        where user_a = least(me, inv.inviter_id) and user_b = greatest(me, inv.inviter_id);
    else
        raise exception 'invite_%', status using errcode = case status
            when 'invalid' then 'PT404'
            when 'own' then 'PT409'
            when 'used' then 'PT409'
            else 'PT410' end;
    end if;
    return jsonb_build_object('status', status, 'connection_id', conn_id);
end;
$$;

-- Open = can still take someone: not full, not cancelled, not expired.
create or replace function public.list_open_invites() returns table (code text, created_at timestamptz, expires_at timestamptz)
language plpgsql security definer set search_path = '' as $$
declare
    me uuid := private.require_user();
begin
    return query
    select i.code, i.created_at, i.expires_at
    from public.invites i
    where i.inviter_id = me and i.uses < i.max_uses and i.revoked_at is null and i.expires_at > now()
    order by i.created_at desc;
end;
$$;

-- Cancelling a code stops further joins; people who already joined stay.
create or replace function public.revoke_invite(p_code text) returns void
language plpgsql security definer set search_path = '' as $$
declare
    me uuid := private.require_user();
begin
    update public.invites set revoked_at = now()
    where code = private.normalize_code(p_code) and inviter_id = me
      and uses < max_uses and revoked_at is null;
    if not found then
        raise exception 'invite_invalid' using errcode = 'PT404';
    end if;
end;
$$;

-- A 6th open invite still retires the oldest, but only codes nobody has used:
-- a code already working in a group chat keeps working.
create or replace function public.create_invite() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
    me uuid := private.require_user();
    new_code text;
    inv public.invites;
begin
    if not exists (select 1 from public.profiles where id = me) then
        raise exception 'profile_required' using errcode = 'PT409';
    end if;
    if (select count(*) from public.invites
        where inviter_id = me and created_at > now() - interval '1 day') >= 20 then
        raise exception 'too_many_invites' using errcode = 'PT429';
    end if;
    update public.invites set revoked_at = now()
    where id in (
        select id from public.invites
        where inviter_id = me and uses = 0 and revoked_at is null and expires_at > now()
        order by created_at desc offset 4
    );
    loop
        new_code := private.new_invite_code();
        begin
            insert into public.invites (code, inviter_id) values (new_code, me) returning * into inv;
            exit;
        exception when unique_violation then
            -- Code collision: try another.
        end;
    end loop;
    return jsonb_build_object('code', inv.code, 'expires_at', inv.expires_at, 'max_uses', inv.max_uses);
end;
$$;

-- "Kim is in": the person who joined this connection with one of the inviter's codes.
create or replace function public.joined_push_targets(p_connection_id uuid) returns jsonb
language sql security definer set search_path = '' as $$
    select jsonb_build_object(
        'connection_id', c.id,
        'joiner_name', j.display_name,
        'sound', r.notification_sound,
        'tokens', coalesce((select jsonb_agg(jsonb_build_object('token', t.token, 'environment', t.environment))
                            from public.device_tokens t where t.user_id = inv.inviter_id), '[]'::jsonb))
    from public.connections c
    join lateral (
        select i.inviter_id, u.user_id as joiner_id from private.invite_uses u
        join public.invites i on i.id = u.invite_id
        where i.inviter_id in (c.user_a, c.user_b) and u.user_id in (c.user_a, c.user_b)
        order by u.accepted_at desc limit 1
    ) inv on true
    join public.profiles j on j.id = inv.joiner_id
    join public.profiles r on r.id = inv.inviter_id
    where c.id = p_connection_id;
$$;

-- Finished invites go 30 days after they end; a used code ends when it expires.
create or replace function private.purge_expired() returns void
language sql security definer set search_path = '' as $$
    delete from public.signal_events where created_at < now() - interval '30 days';
    delete from public.invites where coalesce(revoked_at, expires_at) < now() - interval '30 days';
    delete from private.super_usage where day < (now() at time zone 'UTC')::date - 30;
$$;

-- Daily metrics count every join, not just each code's latest.
create or replace function private.snapshot_metrics(p_day date) returns void
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
        (select count(*) from private.invite_uses where accepted_at >= p_day and accepted_at < p_day + 1),
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
