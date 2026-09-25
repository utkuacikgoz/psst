# Reviewing reports

**Owner decision (25 Sep 2026):** reports stay in the `public.reports` table and the owner reviews them regularly. Apple's guideline 1.2 expects prompt action. Review at least weekly, and more often once real users arrive.

Each report records who reported whom and when. Psst has no message content, so the evidence is the pattern: how many different people reported someone, and how often.

Reporting always blocks the person for the reporter straight away. Your review decides whether anything more is needed.

## Where

Supabase dashboard → the project → **SQL Editor**. Clients can't read this table; the dashboard can.

## New reports (last 7 days)

```sql
select r.created_at,
       reporter.display_name as reporter,
       reported.display_name as reported,
       r.reported_id
from public.reports r
join public.profiles reporter on reporter.id = r.reporter_id
join public.profiles reported on reported.id = r.reported_id
where r.created_at > now() - interval '7 days'
order by r.created_at desc;
```

## People reported by several others

```sql
select reported.display_name, r.reported_id,
       count(distinct r.reporter_id) as reporters,
       max(r.created_at) as latest
from public.reports r
join public.profiles reported on reported.id = r.reported_id
group by 1, 2
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
3. **Remove the account.** Repeated reports from different people, or clear abuse. In the dashboard: Authentication → Users → the user (the same id) → Delete user. That cascades to their profile, connections, invites, signals and device tokens, the same as in-app account deletion. They can make a new anonymous account; if that becomes a pattern, raise it and we'll add a ban list.

Record what you did and when (a private note is enough). Apple can ask how reports are handled.
