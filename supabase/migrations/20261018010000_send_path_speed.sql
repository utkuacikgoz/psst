-- Speed (audit, 18 Oct 2026).
-- latest_doodle runs on every app refresh and widget reload; it filtered every
-- signal you received in 30 days down to doodles row by row. A partial index makes
-- it a short walk over doodles only.
create index if not exists signal_events_recipient_doodle_idx
    on public.signal_events (recipient_id, created_at desc) where effect_id = 'doodle';

-- On every send, the first-two-way trigger ran its EXISTS even for pairs that were
-- marked long ago. Check the mark first.
create or replace function private.mark_first_two_way() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
    if exists (select 1 from public.connections where id = new.connection_id and first_two_way_at is null) then
        update public.connections set first_two_way_at = new.created_at
        where id = new.connection_id and first_two_way_at is null
          and exists (select 1 from public.signal_events
                      where connection_id = new.connection_id and sender_id = new.recipient_id);
    end if;
    return null;
end;
$$;
