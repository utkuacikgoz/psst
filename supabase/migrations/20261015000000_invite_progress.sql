-- 1C (owner pick, 15 Oct 2026): the invite sheet shows your open group code
-- filling up: "3 of 10 joined", who joined, days left. Only the inviter sees it,
-- and only people still connected to them are named (removed or blocked people
-- count, but aren't listed).
create function public.invite_progress() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
    me uuid := private.require_user();
    inv public.invites;
begin
    select * into inv from public.invites i
    where i.inviter_id = me and i.kind = 'code' and i.uses > 0 and i.uses < i.max_uses
      and i.revoked_at is null and i.expires_at > now()
    order by i.created_at desc
    limit 1;
    if inv.id is null then
        return null;
    end if;
    return jsonb_build_object(
        'code', inv.code,
        'expires_at', inv.expires_at,
        'uses', inv.uses,
        'max_uses', inv.max_uses,
        'joined', coalesce((
            select jsonb_agg(p.display_name order by u.accepted_at)
            from private.invite_uses u
            join public.profiles p on p.id = u.user_id
            where u.invite_id = inv.id
              and exists (select 1 from public.connections c
                          where (c.user_a = me and c.user_b = u.user_id) or (c.user_b = me and c.user_a = u.user_id))
              and not exists (select 1 from public.blocks b
                              where (b.blocker_id = me and b.blocked_id = u.user_id)
                                 or (b.blocker_id = u.user_id and b.blocked_id = me))
        ), '[]'::jsonb));
end;
$$;

revoke execute on function public.invite_progress() from public, anon;
grant execute on function public.invite_progress() to authenticated;
