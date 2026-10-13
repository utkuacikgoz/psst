#!/usr/bin/env python3
"""Print why verify-plus refused purchases recently (server-only table; no proofs or keys)."""
import datetime
import json
import os
import subprocess
import urllib.request

ref = os.environ["SUPABASE_PROJECT_REF"]
keys = json.loads(subprocess.run(["supabase", "projects", "api-keys", "--project-ref", ref, "-o", "json"],
                                 check=True, capture_output=True, text=True).stdout)
pick = next((k for k in keys if k.get("name") == "service_role"), None) \
    or next((k for k in keys if k.get("type") == "secret"), None)
if not pick:
    raise SystemExit("Couldn't read the project's service key")
key = pick["api_key"]
print(f"::add-mask::{key}")
headers = {"apikey": key, "Content-Type": "application/json"}
if key.startswith("eyJ"):
    headers["Authorization"] = f"Bearer {key}"
request = urllib.request.Request(f"https://{ref}.supabase.co/rest/v1/rpc/recent_purchase_failures",
                                 data=b"{}", headers=headers, method="POST")
rows = json.load(urllib.request.urlopen(request, timeout=60))
print(f"{len(rows)} verify-plus failure(s) on record (last 7 days, newest first).")
for row in rows:
    print(row["at"], "|", row["stage"], "|", row["reason"])
