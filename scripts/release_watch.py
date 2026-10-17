"""Turns on the soft-update notice once a new version is live on the App Store.

Asks App Store Connect which version is READY_FOR_SALE and its build, and if
public.app_config.latest_build is lower, sets latest_build and latest_version
(home then shows "A new Psst is ready · Update" to older builds, once per
version). Never touches min_build. Prints version numbers only, never keys.
Reads ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8, BUNDLE_ID, SUPABASE_PROJECT_REF and
SUPABASE_ACCESS_TOKEN (for the supabase CLI).
"""
import json
import os
import subprocess
import sys
import urllib.request

sys.path.insert(0, os.path.dirname(__file__))
from release import call  # noqa: E402

apps = call("GET", "/apps", **{"filter[bundleId]": os.environ["BUNDLE_ID"]})["data"]
if not apps:
    sys.exit("No app with that bundle ID in App Store Connect.")
live = call("GET", f"/apps/{apps[0]['id']}/appStoreVersions", **{
    "filter[platform]": "IOS", "filter[appStoreState]": "READY_FOR_SALE", "include": "build", "limit": 1})
if not live["data"]:
    sys.exit("No version is live on the App Store yet.")
version = live["data"][0]["attributes"]["versionString"]
builds = [b for b in live.get("included", []) if b["type"] == "builds"]
if not builds:
    sys.exit(f"Live version {version} has no build attached in the API response.")
build = int(builds[0]["attributes"]["version"])
print(f"Live on the App Store: {version} (build {build}).")

ref = os.environ["SUPABASE_PROJECT_REF"]
keys = json.loads(subprocess.run(["supabase", "projects", "api-keys", "--project-ref", ref, "-o", "json"],
                                 check=True, capture_output=True, text=True).stdout)
pick = next((k for k in keys if k.get("name") == "service_role"), None) \
    or next((k for k in keys if k.get("type") == "secret"), None)
if not pick:
    sys.exit("Couldn't read the project's service key")
secret = pick["api_key"]
print(f"::add-mask::{secret}")
headers = {"apikey": secret, "Content-Type": "application/json"}
if secret.startswith("eyJ"):
    headers["Authorization"] = f"Bearer {secret}"
base = f"https://{ref}.supabase.co/rest/v1/app_config?id=eq.1"
current = json.load(urllib.request.urlopen(urllib.request.Request(
    f"{base}&select=latest_build,latest_version,min_build", headers=headers), timeout=60))[0]
print(f"Psst's app_config: latest_build {current['latest_build']} ({current['latest_version']}), "
      f"min_build {current['min_build']}.")
if current["latest_build"] >= build:
    print("Already up to date; nothing to change.")
    sys.exit(0)
urllib.request.urlopen(urllib.request.Request(
    base, data=json.dumps({"latest_build": build, "latest_version": version}).encode(),
    headers={**headers, "Prefer": "return=minimal"}, method="PATCH"), timeout=60)
print(f"Soft update on: older builds now see \"A new Psst is ready\" for {version} (build {build}).")
