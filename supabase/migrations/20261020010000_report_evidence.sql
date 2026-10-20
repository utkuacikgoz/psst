-- Reports keep their evidence and alert the owner (owner pick 12A, 20 Oct 2026).
--
-- Reporting blocks, and blocking deletes the connection with all its Pssts, so the
-- doodle being reported used to vanish before anyone could look at it. Now the
-- report takes a copy first: the reported doodle (or the reported person's latest
-- doodle to the reporter, within 30 days) and their display name at the time.
-- Reports outlive either account (ids become null), are deleted after 90 days, and
-- nobody can read them from the app. notified_at is set by the hourly Report
-- alerts workflow once the owner has been told (a GitHub issue with ids only).

alter table public.reports
    add column event_id uuid,
    add column evidence jsonb,
    add column reported_name text,
    add column notified_at timestamptz;

-- Deleting either account keeps the report; only its link to the account goes.
alter table public.reports
    alter column reporter_id drop not null,
    alter column reported_id drop not null,
    drop constraint reports_reporter_id_fkey,
    drop constraint reports_reported_id_fkey,
    add constraint reports_reporter_id_fkey foreign key (reporter_id)
        references public.profiles (id) on delete set null,
    add constraint reports_reported_id_fkey foreign key (reported_id)
        references public.profiles (id) on delete set null;

create index reports_reporter_idx on public.reports (reporter_id);
create index reports_unnotified_idx on public.reports (created_at) where notified_at is null;

-- Still no client access at all (RLS on, no policies, no grants).
alter table public.reports enable row level security;
revoke all on public.reports from public, anon, authenticated;

-- p_event_id is optional, so the shipped app (p_user_id only) keeps working.
drop function public.report_user(uuid);
create function public.report_user(p_user_id uuid, p_event_id uuid default null) returns void
language plpgsql security definer set search_path = '' as $$
declare
    me uuid := private.require_user();
    shown public.signal_events;
begin
    if p_user_id is null or p_user_id = me
       or not exists (select 1 from public.profiles where id = p_user_id) then
        raise exception 'invalid_user' using errcode = 'PT422';
    end if;
    -- One open report per pair per day is enough; repeats add nothing.
    if not exists (
        select 1 from public.reports
        where reporter_id = me and reported_id = p_user_id
          and created_at > now() - interval '1 day'
    ) then
        -- The copy is taken before block_user deletes the connection and its Pssts.
        -- A given event counts only if the reported person sent it to the reporter
        -- on the connection between the two.
        if p_event_id is not null then
            select e.* into shown
            from public.signal_events e
            join public.connections c on c.id = e.connection_id
            where e.id = p_event_id and e.sender_id = p_user_id and e.recipient_id = me
              and c.user_a = least(me, p_user_id) and c.user_b = greatest(me, p_user_id);
        end if;
        if shown.id is null then
            select e.* into shown
            from public.signal_events e
            where e.sender_id = p_user_id and e.recipient_id = me
              and e.effect_id = 'doodle' and e.doodle is not null
              and e.created_at > now() - interval '30 days'
            order by e.created_at desc
            limit 1;
        end if;
        insert into public.reports (reporter_id, reported_id, reported_name, event_id, evidence)
        select me, p_user_id, p.display_name, shown.id,
               case when shown.id is not null then jsonb_build_object(
                   'effect', shown.effect_id, 'doodle', shown.doodle, 'created_at', shown.created_at) end
        from public.profiles p
        where p.id = p_user_id;
    end if;
    perform public.block_user(p_user_id);
end;
$$;

revoke execute on function public.report_user(uuid, uuid) from public, anon, authenticated;
grant execute on function public.report_user(uuid, uuid) to authenticated;

-- The daily purge also deletes reports (and their evidence) after 90 days.
create or replace function private.purge_expired() returns void
language sql security definer set search_path = '' as $$
    delete from public.signal_events where created_at < now() - interval '30 days';
    delete from public.invites where coalesce(revoked_at, expires_at) < now() - interval '30 days';
    update public.invites set doodle = null
    where doodle is not null and (revoked_at is not null or expires_at <= now());
    delete from private.super_usage where day < (now() at time zone 'UTC')::date - 30;
    delete from public.reports where created_at < now() - interval '90 days';
$$;
