#!/usr/bin/env python3
"""Prints how long the production edge functions took over the last 24 hours
(Supabase function logs: execution time per request, no bodies or tokens)."""
import datetime
import json
import os
import statistics
import urllib.error
import urllib.parse
import urllib.request

ref = os.environ["SUPABASE_PROJECT_REF"]
token = os.environ["SUPABASE_ACCESS_TOKEN"]
end = datetime.datetime.now(datetime.timezone.utc)
start = end - datetime.timedelta(hours=24)
sql = """
select function_edge_logs.timestamp, request.method, request.pathname, response.status_code, m.execution_time_ms
from function_edge_logs
cross join unnest(metadata) as m
cross join unnest(m.response) as response
cross join unnest(m.request) as request
order by timestamp desc
limit 1000
"""
query = urllib.parse.urlencode({"sql": sql, "iso_timestamp_start": start.isoformat(), "iso_timestamp_end": end.isoformat()})
request = urllib.request.Request(f"https://api.supabase.com/v1/projects/{ref}/analytics/endpoints/logs?{query}",
                                 headers={"Authorization": f"Bearer {token}"})
try:
    body = json.load(urllib.request.urlopen(request, timeout=60))
except urllib.error.HTTPError as error:
    raise SystemExit(f"Logs API refused ({error.code}): {error.read()[:500].decode(errors='replace')}")
if body.get("error"):
    raise SystemExit(f"Logs query failed: {body['error']}")
rows = body.get("result") or []
by_path = {}
for row in rows:
    if row.get("method") != "POST":
        continue
    by_path.setdefault(row.get("pathname") or "?", []).append(float(row.get("execution_time_ms") or 0))
print(f"{len(rows)} edge function requests in the last 24 h.")
for path, times in sorted(by_path.items()):
    times.sort()
    p = lambda q: times[min(len(times) - 1, int(q * len(times)))]
    print(f"{path}: {len(times)} calls · median {statistics.median(times):.0f} ms · p90 {p(0.9):.0f} ms · "
          f"max {times[-1]:.0f} ms")
