-- Unseen Pssts are read on every refresh (list_unseen, and the unseen count in
-- list_connections). Partial indexes keep those reads small as history grows.
create index if not exists signal_events_unseen_recipient_idx
    on public.signal_events (recipient_id, created_at desc) where seen_at is null;
create index if not exists signal_events_unseen_connection_idx
    on public.signal_events (connection_id, recipient_id) where seen_at is null;
