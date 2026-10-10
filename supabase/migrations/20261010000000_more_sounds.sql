-- Psst+ adds three whisper sounds: Double, Low and Long. Same rules as before:
-- the recipient's own choice, named in each push, files shipped in the app.

alter table public.profiles drop constraint profiles_notification_sound_check;
alter table public.profiles add constraint profiles_notification_sound_check
    check (notification_sound in ('psst.wav', 'psst-soft.wav', 'psst-quick.wav',
                                  'psst-double.wav', 'psst-low.wav', 'psst-long.wav'));

create or replace function public.set_notification_sound(p_sound text) returns void
language plpgsql security definer set search_path = '' as $$
declare
    me uuid := private.require_user();
begin
    if p_sound not in ('psst.wav', 'psst-soft.wav', 'psst-quick.wav',
                       'psst-double.wav', 'psst-low.wav', 'psst-long.wav') then
        raise exception 'invalid_sound' using errcode = 'PT422';
    end if;
    update public.profiles set notification_sound = p_sound where id = me;
    if not found then
        raise exception 'profile_required' using errcode = 'PT409';
    end if;
end;
$$;

revoke execute on function public.set_notification_sound(text) from public, anon, authenticated;
grant execute on function public.set_notification_sound(text) to authenticated;
