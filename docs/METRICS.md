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
