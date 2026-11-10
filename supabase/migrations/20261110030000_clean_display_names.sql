-- Clean display names (1.0.9 audit, owner-approved 10 Nov 2026).
--
-- Names appear on other people's phones, notifications, widgets and invite
-- pages, so invisible characters could make a name look empty, reorder the text
-- around it (bidi overrides) or break lines. set_display_name now:
--   * turns control characters and line/paragraph separators into spaces;
--   * removes bidi controls (U+061C, U+200E, U+200F, U+202A-U+202E, U+2066-U+2069),
--     zero-width and invisible characters (U+200B, U+FEFF, U+2060-U+2064, U+180E)
--     and Hangul fillers (U+3164, U+FFA0);
--   * keeps a zero-width joiner or non-joiner (U+200D, U+200C) only between two
--     visible characters, where emoji like a family or a rainbow flag and
--     Persian or Indic names need it; anywhere else it goes;
--   * collapses runs of whitespace to one space and trims the ends;
-- then checks 1 to 40 characters as before ('invalid_name' if empty or too long).
-- No words are refused. Names are only set here (onboarding and rename).

create function private.clean_display_name(p_name text) returns text
language sql immutable set search_path = '' as $$
    select btrim(regexp_replace(regexp_replace(regexp_replace(regexp_replace(
        btrim(regexp_replace(regexp_replace(regexp_replace(
            coalesce(p_name, ''),
            -- control characters and line/paragraph separators become spaces
            '[\u0001-\u001F\u007F-\u009F  ]', ' ', 'g'),
            -- bidi controls, zero-width and invisible characters, Hangul fillers go
            '[؜​‎‏‪-‮⁦-⁩⁠-⁤᠎﻿ㅤﾠ]', '', 'g'),
            -- any run of whitespace becomes one space
            '[\s   -   　]+', ' ', 'g')),
        -- joiners: one at a time, and only between two visible characters
        '([‌‍])[‌‍]+', '\1', 'g'),
        '(^| )[‌‍]+', '\1', 'g'),
        '[‌‍]+( |$)', '\1', 'g'),
        ' +', ' ', 'g'));
$$;

create or replace function public.set_display_name(p_name text) returns void
language plpgsql security definer set search_path = '' as $$
declare
    me uuid := private.require_user();
    cleaned text := private.clean_display_name(p_name);
begin
    if char_length(cleaned) not between 1 and 40 then
        raise exception 'invalid_name' using errcode = 'PT422';
    end if;
    insert into public.profiles (id, display_name) values (me, cleaned)
    on conflict (id) do update set display_name = excluded.display_name;
end;
$$;

revoke execute on function private.clean_display_name(text) from public, anon, authenticated;
