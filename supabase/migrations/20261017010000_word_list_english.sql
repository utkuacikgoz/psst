-- Your word: English only (owner, 17 Oct 2026). Drops "pışt" and "ねぇ"; the list is
-- psst, hey, boop, oi, yo, hiii, mwah, psst psst.
update public.profiles set psst_word = null where psst_word in ('pışt', 'ねぇ');
alter table public.profiles drop constraint profiles_psst_word_check;
alter table public.profiles add constraint profiles_psst_word_check
    check (psst_word is null or psst_word in ('hey', 'boop', 'oi', 'yo', 'hiii', 'mwah', 'psst psst'));

create or replace function public.set_psst_word(p_word text) returns void
language plpgsql security definer set search_path = '' as $$
declare
    me uuid := private.require_user();
    word text := nullif(nullif(btrim(p_word), ''), 'psst');
begin
    if word is not null and word not in ('hey', 'boop', 'oi', 'yo', 'hiii', 'mwah', 'psst psst') then
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
