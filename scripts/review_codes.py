"""Fresh App Review codes for the Psst Team profile, seen only by App Store Connect.

The release workflow calls make() and puts the codes into the reviewer notes in place of
{REVIEW_CODE} and {BACKUP_CODE}. Codes never go into the repo or the log: they're masked
first and only "made" is printed. Each run revokes the review codes earlier runs made (and
only those: the Psst Team's own 7-day app codes are left alone), so only the codes in the
latest notes work. Uses the Supabase Management API (SQL endpoint) with
SUPABASE_ACCESS_TOKEN and SUPABASE_PROJECT_REF (production).
"""
import json
import os
import secrets
import sys
import urllib.error
import urllib.request

# Same alphabet as the database's invite codes (no look-alikes).
ALPHABET = "ABCDEFGHJKMNPQRSTVWXYZ23456789"
USES = 3       # one reviewer, maybe a second, and a spare
DAYS = 30


def code() -> str:
    return "".join(secrets.choice(ALPHABET) for _ in range(8))


def sql(query: str) -> list:
    ref, token = os.environ["SUPABASE_PROJECT_REF"], os.environ["SUPABASE_ACCESS_TOKEN"]
    request = urllib.request.Request(
        f"https://api.supabase.com/v1/projects/{ref}/database/query",
        data=json.dumps({"query": query}).encode(), method="POST",
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"})
    try:
        return json.loads(urllib.request.urlopen(request, timeout=60).read() or b"[]")
    except urllib.error.HTTPError as error:
        # The body can quote the query, which holds the codes: never print it.
        sys.exit(f"Supabase refused the review-code query ({error.code}).")
    except urllib.error.URLError as error:
        sys.exit(f"Couldn't reach Supabase for the review codes ({error.reason}).")


def make() -> tuple[str, str]:
    if not os.environ.get("SUPABASE_ACCESS_TOKEN") or not os.environ.get("SUPABASE_PROJECT_REF"):
        sys.exit("The notes need review codes: set SUPABASE_ACCESS_TOKEN(_PROD) and SUPABASE_PROJECT_REF_PROD "
                 "on the production environment.")
    review, backup = code(), code()
    while backup == review:
        backup = code()
    if os.environ.get("GITHUB_ACTIONS"):
        print(f"::add-mask::{review}")
        print(f"::add-mask::{backup}")
    # One statement, one transaction: both CTEs see the same snapshot, so the update only
    # revokes earlier review codes (never the two inserted here). Review codes are the only
    # code-kind invites with exactly USES joins and a life over 8 days (the app's are 7 days).
    rows = sql(f"""
        with team as (select id from public.profiles where display_name = 'Psst Team' order by created_at limit 1),
        revoked as (
            update public.invites set revoked_at = now()
            where inviter_id = (select id from team) and kind = 'code' and revoked_at is null
              and max_uses = {USES} and expires_at > created_at + interval '8 days'
            returning id)
        insert into public.invites (code, inviter_id, expires_at, max_uses)
        select v.code, team.id, now() + interval '{DAYS} days', {USES}
        from team, (values ('{review}'), ('{backup}')) as v(code)
        returning id""")
    if len(rows) != 2:
        sys.exit("No 'Psst Team' profile in production, so no review codes were made.")
    print(f"Made 2 review codes for Psst Team ({USES} joins each, {DAYS} days); earlier ones revoked.")
    return review, backup
