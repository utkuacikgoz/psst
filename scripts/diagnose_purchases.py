#!/usr/bin/env python3
"""Print verify-plus failure reasons from the Supabase function logs (last 24 hours)."""
import datetime
import json
import os
import urllib.parse
import urllib.request

ref = os.environ["SUPABASE_PROJECT_REF"]
token = os.environ["SUPABASE_ACCESS_TOKEN"]
end = datetime.datetime.now(datetime.timezone.utc)
start = end - datetime.timedelta(hours=23, minutes=59)
sql = ("select timestamp, event_message from function_logs "
       "where event_message like '%verify-plus failed%' order by timestamp desc limit 50")
query = urllib.parse.urlencode({"sql": sql, "iso_timestamp_start": start.isoformat(), "iso_timestamp_end": end.isoformat()})
request = urllib.request.Request(
    f"https://api.supabase.com/v1/projects/{ref}/analytics/endpoints/logs.all?{query}",
    headers={"Authorization": f"Bearer {token}"})
body = json.load(urllib.request.urlopen(request, timeout=60))
if body.get("error"):
    raise SystemExit(f"Log query failed: {body['error']}")
rows = body.get("result") or []
print(f"{len(rows)} verify-plus failure line(s) in the last 24 hours.")
for row in rows:
    stamp = datetime.datetime.fromtimestamp(int(row["timestamp"]) / 1_000_000, datetime.timezone.utc)
    print(stamp.strftime("%Y-%m-%d %H:%M:%S UTC"), row["event_message"].strip())
