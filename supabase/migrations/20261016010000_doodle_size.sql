-- The app allows 60 strokes / 2,000 points (owner pick 1A), rounded to 3 decimals.
-- As jsonb text a point takes up to 16 bytes ("[0.123, 0.456], "), so a full doodle
-- is about 32 KB; the 24 KB cap rejected drawings the app had accepted. Same limits
-- on strokes and points, room for the bytes they need.

alter table public.signal_events drop constraint signal_events_doodle_size;
alter table public.signal_events add constraint signal_events_doodle_size
    check (doodle is null or octet_length(doodle::text) <= 40000);

create or replace function private.valid_doodle(p jsonb) returns boolean
language sql immutable set search_path = '' as $$
    select p is not null and jsonb_typeof(p) = 'array'
       and jsonb_array_length(p) between 1 and 60
       and octet_length(p::text) <= 40000
       and not exists (select 1 from jsonb_array_elements(p) s
                       where jsonb_typeof(s) <> 'array' or jsonb_array_length(s) = 0)
       and (select count(*) from jsonb_array_elements(p) s, jsonb_array_elements(s) pt) <= 2000
       and not exists (
           select 1 from jsonb_array_elements(p) s, jsonb_array_elements(s) pt
           where jsonb_typeof(pt) <> 'array' or jsonb_array_length(pt) <> 2
              or jsonb_typeof(pt -> 0) <> 'number' or jsonb_typeof(pt -> 1) <> 'number'
              or (pt ->> 0)::numeric not between 0 and 1 or (pt ->> 1)::numeric not between 0 and 1);
$$;
