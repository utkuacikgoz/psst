-- Psst+ stays on for a verified buyer (security audit, 18 Oct 2026).
-- A verified purchase counted for only 5 minutes: fine for the Super Psst card,
-- which re-checks before each send, but your word is read when someone receives
-- your Psst, often hours later, so it fell back to "psst". Now:
--   * a verified purchase is valid for 30 days; verify-plus re-asks Apple at most
--     every 6 hours per account (the app checks at launch), so refunds still land;
--   * one purchase covers up to 3 Psst accounts at once (iPhone + iPad on the same
--     Apple ID are separate anonymous accounts); a 4th evicts the one checked
--     longest ago, so a leaked proof can't be shared without limit.

alter table private.plus_entitlements drop constraint plus_entitlements_original_transaction_id_key;
alter table private.plus_entitlements add column verified_at timestamptz not null default now();
create index plus_entitlements_original_idx on private.plus_entitlements (original_transaction_id, verified_at desc);

create or replace function public.record_verified_plus(p_user_id uuid, p_original_id text, p_active boolean)
returns void language plpgsql security definer set search_path = '' as $$
begin
    insert into private.plus_entitlements(user_id, original_transaction_id, valid_until, verified_at)
    values(p_user_id, p_original_id, case when p_active then now() + interval '30 days' else now() end, now())
    on conflict(user_id) do update set
        original_transaction_id = excluded.original_transaction_id,
        valid_until = excluded.valid_until, verified_at = excluded.verified_at;
    -- A refund or revocation ends it for every account holding this purchase.
    if not p_active then
        update private.plus_entitlements set valid_until = now() where original_transaction_id = p_original_id;
    end if;
    delete from private.plus_entitlements
    where original_transaction_id = p_original_id
      and user_id not in (select user_id from private.plus_entitlements
                          where original_transaction_id = p_original_id
                          order by verified_at desc limit 3);
end;
$$;

-- verify-plus skips Apple when this account was checked in the last 6 hours.
create or replace function public.plus_is_current(p_user_id uuid) returns boolean
language sql security definer set search_path = '' as $$
    select exists(select 1 from private.plus_entitlements
                  where user_id = p_user_id and valid_until > now() and verified_at > now() - interval '6 hours');
$$;
