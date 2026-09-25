-- Psst+ whisper sounds: the recipient chooses how Pssts sound on their own
-- phone. The sound files ship in the app; the server only names one in each
-- push. It changes nothing anyone else sees or hears, so it isn't treated as a
-- paid effect: the app offers the choice with Psst+ (see Purchases.swift).

alter table public.profiles add column notification_sound text not null default 'psst.wav'
    check (notification_sound in ('psst.wav', 'psst-soft.wav', 'psst-quick.wav'));

create function public.set_notification_sound(p_sound text) returns void
language plpgsql security definer set search_path = '' as $$
declare
    me uuid := private.require_user();
begin
    if p_sound not in ('psst.wav', 'psst-soft.wav', 'psst-quick.wav') then
        raise exception 'invalid_sound' using errcode = 'PT422';
    end if;
    update public.profiles set notification_sound = p_sound where id = me;
    if not found then
        raise exception 'profile_required' using errcode = 'PT409';
    end if;
end;
$$;

create or replace function public.push_targets(p_event_id uuid) returns jsonb
language sql security definer set search_path = '' as $$
    select jsonb_build_object(
        'event_id', s.id,
        'connection_id', s.connection_id,
        'effect_id', s.effect_id,
        'same_moment', s.same_moment,
        'sound', (select r.notification_sound from public.profiles r where r.id = s.recipient_id),
        'push_status', s.push_status,
        'sender_name', p.display_name,
        'tokens', coalesce((select jsonb_agg(jsonb_build_object('token', t.token, 'environment', t.environment))
                            from public.device_tokens t where t.user_id = s.recipient_id), '[]'::jsonb))
    from public.signal_events s join public.profiles p on p.id = s.sender_id
    where s.id = p_event_id;
$$;

revoke execute on function public.set_notification_sound(text) from public, anon, authenticated;
grant execute on function public.set_notification_sound(text) to authenticated;
