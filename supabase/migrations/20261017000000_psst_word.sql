-- Your word (owner picks 1A 2A 3A, 16 Oct 2026; Psst+): one word, from a fixed list,
-- that the people you psst see instead of "psst", in their notification and the
-- full-screen moment. The name and the verb stay Psst; null = "psst". A fixed list
-- means nothing to moderate. Only shown while the sender's Psst+ is valid.

alter table public.profiles add column psst_word text
    check (psst_word is null or psst_word in
           ('hey', 'boop', 'oi', 'yo', 'hiii', 'mwah', 'pışt', 'ねぇ', 'psst psst'));

create function private.word_of(p_user uuid) returns text
language sql stable set search_path = '' as $$
    select pr.psst_word from public.profiles pr
    where pr.id = p_user
      and exists (select 1 from private.plus_entitlements e where e.user_id = p_user and e.valid_until > now());
$$;
revoke all on function private.word_of(uuid) from public, anon, authenticated;

create function public.set_psst_word(p_word text) returns void
language plpgsql security definer set search_path = '' as $$
declare
    me uuid := private.require_user();
    word text := nullif(nullif(btrim(p_word), ''), 'psst');
begin
    if word is not null and word not in ('hey', 'boop', 'oi', 'yo', 'hiii', 'mwah', 'pışt', 'ねぇ', 'psst psst') then
        raise exception 'invalid_word' using errcode = 'PT422';
    end if;
    if word is not null and not exists (select 1 from private.plus_entitlements
                                        where user_id = me and valid_until > now()) then
        raise exception 'plus_required' using errcode = 'PT403';
    end if;
    update public.profiles set psst_word = word where id = me;
    if not found then
        raise exception 'profile_required' using errcode = 'PT409';
    end if;
end;
$$;

-- Your own choice, for the Psst+ sheet (null = "psst").
create function public.my_psst_word() returns text
language sql stable security definer set search_path = '' as $$
    select psst_word from public.profiles where id = private.require_user();
$$;

revoke execute on function public.set_psst_word(text), public.my_psst_word() from public, anon;
grant execute on function public.set_psst_word(text), public.my_psst_word() to authenticated;

-- Pushes and the unseen list carry the sender's word for plain Pssts only
-- (Super Psst and doodles keep their own wording).
create or replace function public.push_targets(p_event_id uuid) returns jsonb
language sql security definer set search_path = '' as $$
    select jsonb_build_object(
        'event_id',s.id,'connection_id',s.connection_id,
        'effect_id',case when s.effect_id = 'super_psst' and not r.super_effects_enabled then 'psst' else s.effect_id end,
        'same_moment',s.same_moment,
        'sound',case when s.effect_id = 'super_psst' and r.super_effects_enabled then 'psst-super.wav' else r.notification_sound end,
        'push_status',s.push_status,'sender_name',p.display_name,
        'word',case when s.effect_id = 'psst' then private.word_of(s.sender_id) end,
        'tokens',coalesce((select jsonb_agg(jsonb_build_object('token',t.token,'environment',t.environment))
                          from public.device_tokens t where t.user_id = s.recipient_id),'[]'::jsonb))
    from public.signal_events s
    join public.profiles p on p.id = s.sender_id
    join public.profiles r on r.id = s.recipient_id where s.id = p_event_id;
$$;

drop function public.list_unseen();
create function public.list_unseen() returns table (
    id uuid, connection_id uuid, sender_id uuid, sender_name text, effect_id text,
    created_at timestamptz, same_moment boolean, doodle jsonb, word text
) language plpgsql security definer set search_path = '' as $$
declare me uuid := private.require_user();
begin
    return query
    select s.id,s.connection_id,s.sender_id,p.display_name,
           case when s.effect_id = 'super_psst' and not r.super_effects_enabled then 'psst' else s.effect_id end,
           s.created_at,s.same_moment,s.doodle,
           case when s.effect_id = 'psst' then private.word_of(s.sender_id) end
    from public.signal_events s
    join public.profiles p on p.id = s.sender_id
    join public.profiles r on r.id = s.recipient_id
    where s.recipient_id = me and s.seen_at is null
    order by s.created_at desc limit 50;
end;
$$;
revoke execute on function public.list_unseen() from public, anon;
grant execute on function public.list_unseen() to authenticated;
