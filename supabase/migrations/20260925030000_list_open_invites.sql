-- Open invites in Settings (owner pick PI2): your own unused, uncancelled,
-- unexpired invites, newest first. Cancel uses the existing revoke_invite.

create function public.list_open_invites() returns table (code text, created_at timestamptz, expires_at timestamptz)
language plpgsql security definer set search_path = '' as $$
declare
    me uuid := private.require_user();
begin
    return query
    select i.code, i.created_at, i.expires_at
    from public.invites i
    where i.inviter_id = me and i.accepted_at is null and i.revoked_at is null and i.expires_at > now()
    order by i.created_at desc;
end;
$$;

revoke execute on function public.list_open_invites() from public, anon, authenticated;
grant execute on function public.list_open_invites() to authenticated;
