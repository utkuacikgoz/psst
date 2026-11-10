-- Invited or organic (1.0.9 audit, owner-approved 10 Nov 2026).
--
-- Invites and their joins (private.invite_uses) are deleted 30 days after an
-- invite ends, so whether an account came through an invite was lost with them.
-- One small row per account that ever joined with an invite keeps it: invited
-- (it joined within a day of making the account), the kind of link, and when the
-- account was made. No inviter, no code. It goes with the account.
-- The nightly metrics now count invited and organic new accounts, and invites
-- made by kind. See docs/METRICS.md.

create table private.account_origins (
    user_id uuid primary key references public.profiles (id) on delete cascade,
    invited boolean not null,           -- first join came within a day of the account
    invite_kind text check (invite_kind in ('code', 'psst')),  -- that link's kind; null if not invited
    joined_at timestamptz not null      -- when the account was made (profiles.created_at)
);
revoke all on private.account_origins from public, anon, authenticated;

-- Filled by accept_invite's join row: only the first join counts.
create function private.record_account_origin() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
    insert into private.account_origins (user_id, invited, invite_kind, joined_at)
    select new.user_id,
           new.accepted_at <= p.created_at + interval '1 day',
           case when new.accepted_at <= p.created_at + interval '1 day' then i.kind end,
           p.created_at
    from public.profiles p
    join public.invites i on i.id = new.invite_id
    where p.id = new.user_id
    on conflict (user_id) do nothing;
    return null;
end;
$$;

create trigger invite_uses_account_origin
    after insert on private.invite_uses
    for each row execute function private.record_account_origin();

-- From the joins still kept. Older invited accounts whose invites were already
-- purged can't be told apart and count as organic.
insert into private.account_origins (user_id, invited, invite_kind, joined_at)
select p.id,
       f.accepted_at <= p.created_at + interval '1 day',
       case when f.accepted_at <= p.created_at + interval '1 day' then f.kind end,
       p.created_at
from public.profiles p
join lateral (
    select u.accepted_at, i.kind
    from private.invite_uses u
    join public.invites i on i.id = u.invite_id
    where u.user_id = p.id
    order by u.accepted_at
    limit 1
) f on true
on conflict (user_id) do nothing;

-- Null on days before this was measured.
alter table private.metrics_daily
    add column invited_new_accounts int,   -- new accounts that joined with an invite that day or the next
    add column organic_new_accounts int,   -- the other new accounts
    add column code_invites_created int,   -- invite codes made that day (group codes)
    add column psst_invites_created int;   -- Psst links made that day (with or without a doodle)

create or replace function private.snapshot_metrics(p_day date) returns void
language sql security definer set search_path = '' as $$
    with day_signals as (
        select * from public.signal_events
        where created_at >= p_day and created_at < p_day + 1
    ), day_pairs as (
        select connection_id, count(distinct sender_id) as senders
        from day_signals group by connection_id
    ), day_accounts as (
        select p.id, coalesce(o.invited, false) as invited
        from public.profiles p
        left join private.account_origins o on o.user_id = p.id
        where p.created_at >= p_day and p.created_at < p_day + 1
    ), day_invites as (
        select kind from public.invites where created_at >= p_day and created_at < p_day + 1
    )
    insert into private.metrics_daily (
        day, accounts, new_accounts, accepted_invites, connections, signals, active_pairs,
        two_way_pairs, first_two_way_pairs, returning_pairs, push_failed, push_no_devices,
        blocks, reports, notifications_off, notifications_reported,
        invited_new_accounts, organic_new_accounts, code_invites_created, psst_invites_created)
    select
        p_day,
        (select count(*) from public.profiles),
        (select count(*) from day_accounts),
        (select count(*) from private.invite_uses where accepted_at >= p_day and accepted_at < p_day + 1),
        (select count(*) from public.connections),
        (select count(*) from day_signals),
        (select count(*) from day_pairs),
        (select count(*) from day_pairs where senders = 2),
        (select count(*) from public.connections where first_two_way_at >= p_day and first_two_way_at < p_day + 1),
        (select count(*) from day_pairs d join public.connections c on c.id = d.connection_id
         where d.senders = 2 and c.first_two_way_at < p_day),
        (select count(*) from day_signals where push_status = 'failed'),
        (select count(*) from day_signals where push_status = 'no_devices'),
        (select count(*) from public.blocks where created_at >= p_day and created_at < p_day + 1),
        (select count(*) from public.reports where created_at >= p_day and created_at < p_day + 1),
        (select count(*) from public.profiles where notifications_enabled = false),
        (select count(*) from public.profiles where notifications_enabled is not null),
        (select count(*) from day_accounts where invited),
        (select count(*) from day_accounts where not invited),
        (select count(*) from day_invites where kind = 'code'),
        (select count(*) from day_invites where kind = 'psst')
    on conflict (day) do update set
        accounts = excluded.accounts, new_accounts = excluded.new_accounts,
        accepted_invites = excluded.accepted_invites, connections = excluded.connections,
        signals = excluded.signals, active_pairs = excluded.active_pairs,
        two_way_pairs = excluded.two_way_pairs, first_two_way_pairs = excluded.first_two_way_pairs,
        returning_pairs = excluded.returning_pairs, push_failed = excluded.push_failed,
        push_no_devices = excluded.push_no_devices, blocks = excluded.blocks, reports = excluded.reports,
        notifications_off = excluded.notifications_off,
        notifications_reported = excluded.notifications_reported,
        invited_new_accounts = excluded.invited_new_accounts,
        organic_new_accounts = excluded.organic_new_accounts,
        code_invites_created = excluded.code_invites_created,
        psst_invites_created = excluded.psst_invites_created, created_at = now();
$$;

-- The dashboard's report gains the four new counts (null before they existed).
create or replace function public.metrics_report() returns jsonb
language sql stable security definer set search_path = '' as $$
    select jsonb_build_object(
        'generated_at', now(),
        'accounts_now', (select count(*) from public.profiles),
        'plus_now', (select count(*) from private.plus_entitlements where valid_until > now()),
        'days', coalesce((
            select jsonb_agg(jsonb_build_object(
                'day', m.day, 'accounts', m.accounts, 'new_accounts', m.new_accounts,
                'accepted_invites', m.accepted_invites, 'signals', m.signals, 'active_pairs', m.active_pairs,
                'two_way_pairs', m.two_way_pairs, 'first_two_way_pairs', m.first_two_way_pairs,
                'returning_pairs', m.returning_pairs, 'push_failed', m.push_failed,
                'push_no_devices', m.push_no_devices, 'blocks', m.blocks, 'reports', m.reports,
                'invited_new_accounts', m.invited_new_accounts, 'organic_new_accounts', m.organic_new_accounts,
                'code_invites_created', m.code_invites_created, 'psst_invites_created', m.psst_invites_created)
                order by m.day)
            from private.metrics_daily m
            where m.day > current_date - 60), '[]'::jsonb));
$$;

revoke execute on function private.record_account_origin() from public, anon, authenticated;
