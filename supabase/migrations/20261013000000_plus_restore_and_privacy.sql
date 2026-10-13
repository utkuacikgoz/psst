-- 1. Psst+ follows the person, not the old account. Accounts are anonymous and
--    stay on one phone, so a restore on a new phone is a new account: the newest
--    account that proves the purchase (Apple-signed, checked server-side) holds
--    the entitlement, and the previous one stops being unlimited.
create or replace function public.record_verified_plus(p_user_id uuid, p_original_id text, p_active boolean)
returns void language plpgsql security definer set search_path = '' as $$
begin
    delete from private.plus_entitlements
    where original_transaction_id = p_original_id and user_id <> p_user_id;
    insert into private.plus_entitlements(user_id, original_transaction_id, valid_until)
    values(p_user_id, p_original_id, case when p_active then now() + interval '5 minutes' else now() end)
    on conflict(user_id) do update set
        original_transaction_id = excluded.original_transaction_id, valid_until = excluded.valid_until;
end;
$$;

-- Lets verify-plus skip Apple when this account was verified in the last few minutes.
create function public.plus_is_current(p_user_id uuid) returns boolean
language sql security definer set search_path = '' as $$
    select exists(select 1 from private.plus_entitlements where user_id = p_user_id and valid_until > now());
$$;
revoke execute on function public.plus_is_current(uuid) from public, anon, authenticated;
grant execute on function public.plus_is_current(uuid) to service_role;

-- 2. Connected people may read each other's name, nothing else on the profile
--    (notification and sound settings stay private).
revoke select on public.profiles from authenticated;
grant select (id, display_name, created_at) on public.profiles to authenticated;

-- 3. Opening "Share my invite" makes a code; doing it a few times used to hit the
--    5-open-invites limit and block sharing. Now a 6th open invite retires the
--    oldest unused one instead. A daily cap still stops code spam.
create or replace function public.create_invite() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
    me uuid := private.require_user();
    new_code text;
    inv public.invites;
begin
    if not exists (select 1 from public.profiles where id = me) then
        raise exception 'profile_required' using errcode = 'PT409';
    end if;
    if (select count(*) from public.invites
        where inviter_id = me and created_at > now() - interval '1 day') >= 20 then
        raise exception 'too_many_invites' using errcode = 'PT429';
    end if;
    update public.invites set revoked_at = now()
    where id in (
        select id from public.invites
        where inviter_id = me and accepted_at is null and revoked_at is null and expires_at > now()
        order by created_at desc offset 4
    );
    loop
        new_code := private.new_invite_code();
        begin
            insert into public.invites (code, inviter_id) values (new_code, me) returning * into inv;
            exit;
        exception when unique_violation then
            -- Code collision: try another.
        end;
    end loop;
    return jsonb_build_object('code', inv.code, 'expires_at', inv.expires_at);
end;
$$;
