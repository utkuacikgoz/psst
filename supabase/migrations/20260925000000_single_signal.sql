-- The owner reduced the app to a single signal, Psst (25 Sep 2026).
-- Squeeze, Oi and Duck are removed and per-connection favourites retired.
-- The effects table stays so future effect collections can be added.

update public.connections set a_favorite = 'psst', b_favorite = 'psst'
where a_favorite <> 'psst' or b_favorite <> 'psst';

-- Development data only: signals that used a removed effect.
delete from public.signal_events where effect_id <> 'psst';

delete from public.effects where id <> 'psst';

drop function if exists public.set_favorite(uuid, text);
