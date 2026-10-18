-- Doodle as the invite (owner picks 1A 2A 3A 4A, 18 Oct 2026). A Psst link can hold
-- a drawing instead of a plain Psst: "Utku drew you something", sealed until they
-- join. The strokes stay here, never on the web page or its preview (those only
-- learn that there is one), and arrive as their first moment when they join.
-- Same link as a Psst link: one person, seven days, the day-5 reminder.

alter table public.invites add column doodle jsonb;
alter table public.invites add constraint invites_doodle_check
    check (doodle is null or (kind = 'psst' and octet_length(doodle::text) <= 40000));

drop function public.create_psst_invite();
create function public.create_psst_invite(p_doodle jsonb default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
    me uuid := private.require_user();
    new_code text;
    inv public.invites;
begin
    if not exists (select 1 from public.profiles where id = me) then
        raise exception 'profile_required' using errcode = 'PT409';
    end if;
    if p_doodle is not null and not private.valid_doodle(p_doodle) then
        raise exception 'invalid_doodle' using errcode = 'PT422';
    end if;
    if (select count(*) from public.invites
        where inviter_id = me and created_at > now() - interval '1 day') >= 20 then
        raise exception 'too_many_invites' using errcode = 'PT429';
    end if;
    loop
        new_code := private.new_invite_code();
        begin
            insert into public.invites (code, inviter_id, kind, max_uses, doodle)
            values (new_code, me, 'psst', 1, p_doodle) returning * into inv;
            exit;
        exception when unique_violation then
            -- Code collision: try another.
        end;
    end loop;
    return jsonb_build_object('code', inv.code, 'expires_at', inv.expires_at, 'max_uses', inv.max_uses,
                              'kind', inv.kind, 'doodle', inv.doodle is not null);
end;
$$;

revoke execute on function public.create_psst_invite(jsonb) from public, anon, authenticated;
grant execute on function public.create_psst_invite(jsonb) to authenticated;

create or replace function public.accept_invite(p_code text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
    me uuid := private.require_user();
    inv public.invites;
    status text;
    conn_id uuid;
    held boolean := false;
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
        -- The drawing moves to their first moment; the link keeps no copy.
        update public.invites set uses = uses + 1, accepted_by = me, accepted_at = now(), doodle = null
        where id = inv.id;
        insert into private.invite_uses (invite_id, user_id) values (inv.id, me)
        on conflict (invite_id, user_id) do update set accepted_at = now();
        -- 5A: the Psst the link was holding (or its doodle) arrives as their first,
        -- sent when the link was.
        if inv.kind = 'psst' then
            insert into public.signal_events (id, connection_id, sender_id, recipient_id, effect_id, doodle, created_at)
            values (gen_random_uuid(), conn_id, inv.inviter_id, me,
                    case when inv.doodle is null then 'psst' else 'doodle' end, inv.doodle, inv.created_at);
            held := true;
        end if;
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
    return jsonb_build_object('status', status, 'connection_id', conn_id, 'held_psst', held);
end;
$$;

-- The web page and its preview learn only that a drawing is waiting.
create or replace function public.public_invite_card(p_code text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
    inv public.invites;
begin
    select * into inv from public.invites where code = private.normalize_code(p_code);
    if inv.id is null or inv.uses >= inv.max_uses or inv.revoked_at is not null or inv.expires_at <= now() then
        return jsonb_build_object('status', 'unavailable');
    end if;
    return jsonb_build_object(
        'status', 'pending',
        'kind', inv.kind,
        'doodle', inv.doodle is not null,
        'first_name', split_part(btrim((select display_name from public.profiles where id = inv.inviter_id)), ' ', 1),
        'expires_at', inv.expires_at);
end;
$$;

-- "Kim is in · Kim got your doodle and joined."
create or replace function public.joined_push_targets(p_connection_id uuid) returns jsonb
language sql security definer set search_path = '' as $$
    select jsonb_build_object(
        'connection_id', c.id,
        'joiner_name', j.display_name,
        'held_psst', inv.kind = 'psst',
        'held_doodle', inv.kind = 'psst' and exists (
            select 1 from public.signal_events s
            where s.connection_id = c.id and s.sender_id = inv.inviter_id and s.effect_id = 'doodle'),
        'sound', r.notification_sound,
        'tokens', coalesce((select jsonb_agg(jsonb_build_object('token', t.token, 'environment', t.environment))
                            from public.device_tokens t where t.user_id = inv.inviter_id), '[]'::jsonb))
    from public.connections c
    join lateral (
        select i.inviter_id, i.kind, u.user_id as joiner_id from private.invite_uses u
        join public.invites i on i.id = u.invite_id
        where i.inviter_id in (c.user_a, c.user_b) and u.user_id in (c.user_a, c.user_b)
        order by u.accepted_at desc limit 1
    ) inv on true
    join public.profiles j on j.id = inv.joiner_id
    join public.profiles r on r.id = inv.inviter_id
    where c.id = p_connection_id;
$$;

-- A drawing on a link nobody used is dropped once the link is cancelled or expires.
create or replace function private.purge_expired() returns void
language sql security definer set search_path = '' as $$
    delete from public.signal_events where created_at < now() - interval '30 days';
    delete from public.invites where coalesce(revoked_at, expires_at) < now() - interval '30 days';
    update public.invites set doodle = null
    where doodle is not null and (revoked_at is not null or expires_at <= now());
    delete from private.super_usage where day < (now() at time zone 'UTC')::date - 30;
$$;

-- Cancelling a doodle link drops its drawing straight away.
create function private.drop_revoked_doodle() returns trigger
language plpgsql set search_path = '' as $$
begin
    if new.revoked_at is not null then
        new.doodle := null;
    end if;
    return new;
end;
$$;

create trigger invites_drop_revoked_doodle before update of revoked_at on public.invites
    for each row when (new.doodle is not null) execute function private.drop_revoked_doodle();
