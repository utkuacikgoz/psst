-- Widget read pass (1.0.9 audit, owner-approved 10 Nov 2026).
--
-- The widget runs in its own process and shouldn't hold the account's session
-- (refreshing it there rotates the refresh token under the app). Instead the app
-- registers a random widget token once, and the widget reads its state with only
-- that token, through the anon key:
--
--   register_widget_token(p_token)  signed in; stores sha256(token), one per account
--   widget_state(p_token)           anon; the doodle and each person's last Psst/streak
--
-- Only the token's hash is stored. Registering again replaces the account's token
-- (the old one stops working). Deleting the account deletes the token with the
-- profile (on delete cascade). An unknown token reads null, with no detail.

create table private.widget_tokens (
    user_id uuid primary key references public.profiles (id) on delete cascade,
    token_hash bytea not null unique,
    created_at timestamptz not null default now()
);
revoke all on private.widget_tokens from public, anon, authenticated;

-- latest_doodle's rule, for any one person: the newest doodle sent to them that
-- they haven't answered (no signal from them to that person since), while still
-- connected and not blocked either way.
create function private.latest_doodle_for(p_user uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
    select jsonb_build_object('event_id', s.id, 'connection_id', s.connection_id,
                              'sender_name', p.display_name, 'created_at', s.created_at, 'doodle', s.doodle)
    from public.signal_events s
    join public.profiles p on p.id = s.sender_id
    where s.recipient_id = p_user and s.effect_id = 'doodle' and s.doodle is not null
      and exists (select 1 from public.connections c where c.id = s.connection_id)
      and not private.is_blocked(s.recipient_id, s.sender_id)
      and not exists (select 1 from public.signal_events r
                      where r.connection_id = s.connection_id and r.sender_id = s.recipient_id
                        and r.created_at > s.created_at)
    order by s.created_at desc
    limit 1;
$$;

-- Same result as before, now from the shared rule.
create or replace function public.latest_doodle() returns jsonb
language sql stable security definer set search_path = '' as $$
    select private.latest_doodle_for(private.require_user());
$$;

create function public.register_widget_token(p_token text) returns void
language plpgsql security definer set search_path = '' as $$
declare
    me uuid := private.require_user();
begin
    if p_token is null or char_length(p_token) not between 32 and 128 then
        raise exception 'invalid_token' using errcode = 'PT422';
    end if;
    if not exists (select 1 from public.profiles where id = me) then
        raise exception 'profile_required' using errcode = 'PT409';
    end if;
    begin
        insert into private.widget_tokens (user_id, token_hash)
        values (me, sha256(convert_to(p_token, 'UTF8')))
        on conflict (user_id) do update set token_hash = excluded.token_hash, created_at = now();
    exception when unique_violation then
        -- Another account holds this token: never move or reveal it.
        raise exception 'invalid_token' using errcode = 'PT422';
    end;
end;
$$;

-- {"doodle": latest_doodle() for the token's account, or null,
--  "people": [{"connection_id", "last_received_at", "streak_days"}, ...]}
-- last_received_at is their newest Psst (any kind) to this account on that
-- connection, within the 30 days signals are kept; null if none. streak_days is
-- list_connections' value: 0 once a streak is broken.
create function public.widget_state(p_token text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
    me uuid;
begin
    if p_token is null or char_length(p_token) not between 32 and 128 then
        return null;
    end if;
    select w.user_id into me from private.widget_tokens w
    where w.token_hash = sha256(convert_to(p_token, 'UTF8'));
    if me is null then
        return null;
    end if;
    return jsonb_build_object(
        'doodle', private.latest_doodle_for(me),
        'people', coalesce((
            select jsonb_agg(jsonb_build_object(
                       'connection_id', c.id,
                       'last_received_at', (
                           select max(s.created_at) from public.signal_events s
                           where s.connection_id = c.id and s.recipient_id = me
                             and s.sender_id = case when c.user_a = me then c.user_b else c.user_a end),
                       'streak_days', private.streak_days(c.id, me))
                   order by c.id)
            from public.connections c
            where me in (c.user_a, c.user_b)), '[]'::jsonb));
end;
$$;

revoke execute on function private.latest_doodle_for(uuid), public.register_widget_token(text),
    public.widget_state(text) from public, anon, authenticated;
grant execute on function public.register_widget_token(text) to authenticated;
grant execute on function public.widget_state(text) to anon, authenticated;
