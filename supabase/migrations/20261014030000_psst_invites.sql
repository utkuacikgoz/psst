-- The Psst is the invite (owner pick 5A, 14 Oct 2026). Psst someone who isn't on
-- Psst yet: they get a link that holds your actual Psst. Joining with it connects
-- you as any invite does, and your Psst arrives as their first one. One person,
-- seven days, and nothing reaches them until they open the link and say yes.

alter table public.invites add column kind text not null default 'code' check (kind in ('code', 'psst'));

create function public.create_psst_invite() returns jsonb
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
    loop
        new_code := private.new_invite_code();
        begin
            insert into public.invites (code, inviter_id, kind, max_uses)
            values (new_code, me, 'psst', 1) returning * into inv;
            exit;
        exception when unique_violation then
            -- Code collision: try another.
        end;
    end loop;
    return jsonb_build_object('code', inv.code, 'expires_at', inv.expires_at, 'max_uses', inv.max_uses, 'kind', inv.kind);
end;
$$;

-- Making codes retires only plain codes nobody used; a waiting Psst stays.
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
        where inviter_id = me and kind = 'code' and uses = 0 and revoked_at is null and expires_at > now()
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
    return jsonb_build_object('code', inv.code, 'expires_at', inv.expires_at, 'max_uses', inv.max_uses, 'kind', inv.kind);
end;
$$;

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
        update public.invites set uses = uses + 1, accepted_by = me, accepted_at = now() where id = inv.id;
        insert into private.invite_uses (invite_id, user_id) values (inv.id, me)
        on conflict (invite_id, user_id) do update set accepted_at = now();
        -- 5A: the Psst the link was holding arrives as their first, sent when the link was.
        if inv.kind = 'psst' then
            insert into public.signal_events (id, connection_id, sender_id, recipient_id, effect_id, created_at)
            values (gen_random_uuid(), conn_id, inv.inviter_id, me, 'psst', inv.created_at);
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

create or replace function public.preview_invite(p_code text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
    me uuid := private.require_user();
    inv public.invites;
    status text;
begin
    select * into inv from public.invites where code = private.normalize_code(p_code);
    status := private.invite_status(inv, me);
    return jsonb_build_object(
        'status', status,
        'kind', coalesce(inv.kind, 'code'),
        'inviter_name', case when status in ('pending', 'already_connected')
            then (select display_name from public.profiles where id = inv.inviter_id) end
    );
end;
$$;

-- For the invite web page and its link preview (no account): the inviter's first
-- name and what kind of invite it is, only while it can still be used.
create function public.public_invite_card(p_code text) returns jsonb
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
        'first_name', split_part(btrim((select display_name from public.profiles where id = inv.inviter_id)), ' ', 1),
        'expires_at', inv.expires_at);
end;
$$;

drop function public.list_open_invites();
create function public.list_open_invites() returns table (code text, created_at timestamptz, expires_at timestamptz, kind text)
language plpgsql security definer set search_path = '' as $$
declare
    me uuid := private.require_user();
begin
    return query
    select i.code, i.created_at, i.expires_at, i.kind
    from public.invites i
    where i.inviter_id = me and i.uses < i.max_uses and i.revoked_at is null and i.expires_at > now()
    order by i.created_at desc;
end;
$$;

-- "Kim is in", and whether Kim joined through your Psst (the push says so).
create or replace function public.joined_push_targets(p_connection_id uuid) returns jsonb
language sql security definer set search_path = '' as $$
    select jsonb_build_object(
        'connection_id', c.id,
        'joiner_name', j.display_name,
        'held_psst', inv.kind = 'psst',
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

revoke execute on function public.create_psst_invite(), public.public_invite_card(text), public.list_open_invites()
    from public, anon, authenticated;
grant execute on function public.create_psst_invite(), public.list_open_invites() to authenticated;
grant execute on function public.public_invite_card(text) to anon, authenticated;
