#!/usr/bin/env python3
"""Daily numbers for the private dashboard (6A): reads public.metrics_report()
(counts only) with the service key and encrypts it for the dashboard, which holds
the only private key. Prints nothing about the numbers: this repo's logs are public.
Needs SUPABASE_PROJECT_REF and the Supabase CLI; writes metrics.enc."""
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
request = urllib.request.Request(f"https://{ref}.supabase.co/rest/v1/rpc/metrics_report", data=b"{}",
                                 headers=headers, method="POST")
report = urllib.request.urlopen(request, timeout=60).read()
json.loads(report)  # must be valid JSON
with open("metrics.json", "wb") as out:
    out.write(report)
subprocess.run(["openssl", "cms", "-encrypt", "-binary", "-aes256", "-in", "metrics.json", "-outform", "DER",
                "-out", "metrics.enc", os.path.join(os.path.dirname(__file__), "metrics_public.pem")], check=True)
os.remove("metrics.json")
print(f"Encrypted {len(report)} bytes of daily counts for the dashboard.")
