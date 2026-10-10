# Measuring Psst

The goal is to learn whether people come back to psst each other voluntarily. The measurement uses the database and nothing else: no analytics SDK, no third parties, no content.

## What's collected for this

- Everything below is counted from data the app already needs: accounts, invites, connections, signals (kept 30 days), blocks and reports.
- One extra fact per person: whether notifications are on (`profiles.notifications_enabled`). The app reports it only when it changes.
- For each pair, the time of their first two-way exchange (`connections.first_two_way_at`).
- Every night at 00:10 UTC, `private.metrics_daily` stores that day's **counts only**: no ids, names or content. The daily rows survive the 30-day signal purge and account deletions.

## Where to look

Supabase dashboard → SQL Editor. Clients can't read any of this.

### The last 30 days

```sql
select day, new_accounts, accepted_invites, signals, active_pairs,
       two_way_pairs, first_two_way_pairs, returning_pairs,
       push_failed, push_no_devices, blocks, reports,
       notifications_off, notifications_reported
from private.metrics_daily
order by day desc
limit 30;
```

### The questions that matter

```sql
-- Do invites turn into real exchanges? (accepted → first two-way)
select sum(accepted_invites) as accepted, sum(first_two_way_pairs) as became_two_way
from private.metrics_daily where day > current_date - 30;

-- Do pairs come back? Pairs that exchanged again on a later day.
select date_trunc('week', day) as week, sum(returning_pairs) as returning_pair_days,
       sum(two_way_pairs) as two_way_pair_days
from private.metrics_daily group by 1 order by 1 desc;

-- Is delivery healthy? Share of signals whose push failed or had no device.
select day, signals, push_failed, push_no_devices from private.metrics_daily order by day desc limit 14;

-- How many people turned notifications off?
select day, notifications_off, notifications_reported from private.metrics_daily order by day desc limit 1;
```

### Do pairs keep pssting? (day 3 and day 7)

The one to check weekly. Divide still_pssting by old_enough for each day.

```sql
-- Do pairs keep pssting? One row per week of first two-way exchanges.
-- A pair "is still pssting" at day 3 (or 7) if either person sent a Psst
-- 3 (or 7) or more days after their first two-way exchange. Only pairs old
-- enough to have reached that day are counted, and only the last 23 days of
-- pairs are used, because signals are deleted after 30 days.
with pairs as (
    select c.id, c.first_two_way_at,
           max(s.created_at) as last_psst
    from public.connections c
    left join public.signal_events s on s.connection_id = c.id
    where c.first_two_way_at > now() - interval '23 days'
    group by c.id, c.first_two_way_at
)
select date_trunc('week', first_two_way_at)::date as week_of_first_exchange,
       count(*) as pairs,
       count(*) filter (where first_two_way_at <= now() - interval '3 days') as old_enough_for_day_3,
       count(*) filter (where last_psst >= first_two_way_at + interval '3 days') as still_pssting_day_3,
       count(*) filter (where first_two_way_at <= now() - interval '7 days') as old_enough_for_day_7,
       count(*) filter (where last_psst >= first_two_way_at + interval '7 days') as still_pssting_day_7
from pairs
group by 1
order by 1 desc;
```

### Today, before the nightly snapshot

```sql
select private.snapshot_metrics(current_date);
select * from private.metrics_daily where day = current_date;
```

Re-running a day replaces its row. Past days can be rebuilt only while their signals are within the 30-day retention.

## Reading it honestly

- A download is not a user, and a signal is not a relationship. The numbers to watch are **returning pairs**: two people who exchange on more than one day.
- `push_failed` and `push_no_devices` count APNs hand-offs, not delivery. The "seen" state in the app is the only evidence a Psst was actually shown.
- Psst+ purchases happen in Apple's systems. Read those in App Store Connect → Sales and Trends; the server doesn't record them.
