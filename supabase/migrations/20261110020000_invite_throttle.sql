-- Invite code guessing (1.0.9 audit, owner-approved 10 Nov 2026).
--
-- 1. preview_invite and accept_invite had no attempt limit. Each account now gets
--    20 misses an hour (a code that doesn't exist, or is used up, cancelled or
--    expired). After that both answer 'too_many_attempts' (HTTP 429) until the
--    next hour, even for a good code. The app shows its usual "Couldn't check that
--    code" / "Couldn't connect" message for it.
--    A raised error rolls back everything in its request, the count included, so
--    accept_invite now *returns* its miss refusals with the HTTP status set
--    (PostgREST's response.status): the same status and the same body
--    ({"code": "PT404", "message": "invite_invalid", ...}) the app got before.
--    public_invite_card (the web page and link preview) stays as it is: it is
--    read-only, answers only "pending" or "unavailable", and Vercel calls it with
--    the public anon key, so a per-person limit isn't possible there.
-- 2. Invite codes drew their letters from gen_random_uuid() bytes, which include
--    the UUID's fixed version and variant bits, and byte % 30 favoured the first
--    16 letters. Now: pgcrypto's random bytes, rejecting 240..255, so every one
--    of the 30 letters is equally likely. Still 8 characters.

create table private.invite_attempts (
    key text not null,                -- the account (auth.uid())
    window_start timestamptz not null, -- the UTC hour
    failures int not null default 0,
    primary key (key, window_start)
);
revoke all on private.invite_attempts from public, anon, authenticated;

create function private.check_invite_attempts(p_key text) returns void
language plpgsql stable security definer set search_path = '' as $$
begin
    if coalesce((select a.failures from private.invite_attempts a
                 where a.key = p_key and a.window_start = date_trunc('hour', now(), 'UTC')), 0) >= 20 then
        raise exception 'too_many_attempts' using errcode = 'PT429';
    end if;
end;
$$;

create function private.note_invite_miss(p_key text) returns void
language sql security definer set search_path = '' as $$
    insert into private.invite_attempts as a (key, window_start, failures)
    values (p_key, date_trunc('hour', now(), 'UTC'), 1)
    on conflict (key, window_start) do update set failures = a.failures + 1;
$$;

-- A refusal answered without raising, so the request's writes are kept. PostgREST
-- sends it with this HTTP status; the body matches a raised PTxxx error's.
create function private.refusal(p_message text, p_status int) returns jsonb
language plpgsql set search_path = '' as $$
begin
    perform set_config('response.status', p_status::text, true);
    return jsonb_build_object('code', 'PT' || p_status, 'details', null, 'hint', null, 'message', p_message);
end;
$$;

create or replace function public.preview_invite(p_code text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
    me uuid := private.require_user();
    inv public.invites;
    status text;
begin
    perform private.check_invite_attempts(me::text);
    select * into inv from public.invites where code = private.normalize_code(p_code);
    status := private.invite_status(inv, me);
    if status in ('invalid', 'used', 'revoked', 'expired') then
        perform private.note_invite_miss(me::text);
    end if;
    return jsonb_build_object(
        'status', status,
        'kind', coalesce(inv.kind, 'code'),
        'inviter_name', case when status in ('pending', 'already_connected')
            then (select display_name from public.profiles where id = inv.inviter_id) end
    );
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
    perform private.check_invite_attempts(me::text);
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
    elsif status = 'own' then
        raise exception 'invite_own' using errcode = 'PT409';
    else
        -- A miss: counted, then refused without raising so the count is kept.
        perform private.note_invite_miss(me::text);
        return private.refusal('invite_' || status, case status
            when 'invalid' then 404
            when 'used' then 409
            else 410 end);
    end if;
    return jsonb_build_object('status', status, 'connection_id', conn_id, 'held_psst', held);
end;
$$;

-- Every letter equally likely: bytes 240..255 are skipped (240 = 8 x 30).
create or replace function private.new_invite_code() returns text
language plpgsql volatile set search_path = '' as $$
declare
    alphabet constant text := 'ABCDEFGHJKMNPQRSTVWXYZ23456789';
    bytes bytea;
    b int;
    result text := '';
begin
    while char_length(result) < 8 loop
        bytes := extensions.gen_random_bytes(16);
        for i in 0..15 loop
            b := get_byte(bytes, i);
            if b < 240 then
                result := result || substr(alphabet, 1 + b % 30, 1);
                exit when char_length(result) = 8;
            end if;
        end loop;
    end loop;
    return result;
end;
$$;

-- The daily purge also drops attempt counts older than a day.
create or replace function private.purge_expired() returns void
language sql security definer set search_path = '' as $$
    delete from public.signal_events where created_at < now() - interval '30 days';
    delete from public.invites where coalesce(revoked_at, expires_at) < now() - interval '30 days';
    update public.invites set doodle = null
    where doodle is not null and (revoked_at is not null or expires_at <= now());
    delete from private.super_usage where day < (now() at time zone 'UTC')::date - 30;
    delete from public.reports where created_at < now() - interval '90 days';
    delete from private.invite_attempts where window_start < now() - interval '1 day';
$$;

revoke execute on function private.check_invite_attempts(text), private.note_invite_miss(text),
    private.refusal(text, int), private.new_invite_code() from public, anon, authenticated;
