# Reviewing reports

**Owner decision (25 Sep 2026):** reports stay in the `public.reports` table and the owner reviews them. **Owner pick 12A (20 Oct 2026):** review every report **within 24 hours** (the terms promise this; Apple's guideline 1.2 expects prompt action), and the evidence is kept with the report.

Each report records:

- who reported whom and when (`reporter_id`, `reported_id`, `created_at`), and the reported person's display name at that moment (`reported_name`);
- **evidence**: a copy of the doodle being reported (`event_id`, and `evidence` = its effect, strokes and time). The copy is taken before the report's block deletes the connection and its Pssts. When the app names the doodle, that one is kept (only if the reported person sent it to the reporter); otherwise it's the reported person's latest doodle to the reporter within 30 days, or nothing. A plain Psst has no content, so a report without a doodle is about the name or the pattern: how many different people reported someone, and how often.

Reports are kept for **90 days** and then deleted by the daily purge (`private.purge_expired`), evidence included. Deleting either account doesn't delete the report: its id becomes empty and `reported_name` and the evidence stay until the 90 days are up.

Reporting always blocks the person for the reporter straight away. Your review decides whether anything more is needed.

## Alerts

The **Report alerts** workflow runs hourly and opens one GitHub issue (assigned to you) whenever there are new reports: the count, the report ids and times, whether a doodle was kept, and the query to open them. The repo is public, so the issue never holds names or drawings. It then sets `notified_at` on those reports. Close the issue once you've reviewed them. It needs `SUPABASE_PROJECT_REF_PROD` and `SUPABASE_ACCESS_TOKEN_PROD` (or `SUPABASE_ACCESS_TOKEN`) on the production environment, the same secrets as the Release workflow.

## Where

Supabase dashboard → the project → **SQL Editor**. Clients can't read this table; the dashboard can.

## New reports (last 7 days)

```sql
select r.id, r.created_at,
       reporter.display_name as reporter,
       r.reported_name as reported,
       reported.display_name as reported_now,
       r.reported_id,
       r.evidence is not null as doodle_kept
from public.reports r
left join public.profiles reporter on reporter.id = r.reporter_id
left join public.profiles reported on reported.id = r.reported_id
where r.created_at > now() - interval '7 days'
order by r.created_at desc;
```

An empty `reporter` or `reported_now` means that account has since been deleted.

## Look at a reported doodle

This turns the kept strokes into an SVG. Copy the result into a file ending in `.svg` and open it:

```sql
select '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1 1" width="600" height="600">'
       || string_agg('<polyline fill="none" stroke="black" stroke-width="0.01" stroke-linecap="round" points="'
                     || (select string_agg((p ->> 0) || ',' || (p ->> 1), ' ') from jsonb_array_elements(s) p)
                     || '"/>', '')
       || '</svg>'
from public.reports r, jsonb_array_elements(r.evidence -> 'doodle') s
where r.id = '<report id>';
```

## People reported by several others

```sql
select r.reported_id, max(r.reported_name) as name,
       count(distinct r.reporter_id) as reporters,
       max(r.created_at) as latest
from public.reports r
where r.reported_id is not null
group by 1
having count(distinct r.reporter_id) >= 2
order by reporters desc, latest desc;
```

## Offensive display names

A display name is the only text a person can write, and reports are most likely about names. Check suspicious ones:

```sql
select id, display_name, created_at from public.profiles
where display_name ~* '<word>|<word>'
order by created_at desc;
```

## Actions

Reversible first:

1. **Nothing more.** One report, nothing else suspicious. The reporter has already blocked them.
2. **Rename.** The name is the problem:
   `update public.profiles set display_name = 'Psst user' where id = '<id>';`
3. **Remove the account.** Repeated reports from different people, or clear abuse. In the dashboard: Authentication → Users → the user (the same id) → Delete user. That cascades to their profile, connections, invites, signals and device tokens, the same as in-app account deletion. Reports about them stay (with an empty id) until their 90 days are up. They can make a new anonymous account; if that becomes a pattern, raise it and we'll add a ban list.

Record what you did and when (a private note is enough, not the public issue). Apple can ask how reports are handled.
