"""Prints App Store Connect's measured download and install sizes for recent builds.

Apple measures each uploaded build per device after processing (thinned, the
way people actually get it). Reads ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8 and
BUNDLE_ID; prints sizes only, never keys.
"""
import json
import os
import statistics
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import jwt

API = "https://api.appstoreconnect.apple.com/v1"
LIMIT = int(os.environ.get("BUILDS", "12"))


def key() -> str:
    body = "".join(l for l in os.environ["ASC_KEY_P8"].splitlines() if "-----" not in l)
    body = "".join(body.split())
    lines = "\n".join(body[i:i + 64] for i in range(0, len(body), 64))
    return f"-----BEGIN PRIVATE KEY-----\n{lines}\n-----END PRIVATE KEY-----\n"


TOKEN = jwt.encode(
    {"iss": os.environ["ASC_ISSUER_ID"], "iat": int(time.time()), "exp": int(time.time()) + 1200,
     "aud": "appstoreconnect-v1"},
    key(), algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})


def get(path: str, **query) -> dict:
    url = f"{API}{path}" + (f"?{urllib.parse.urlencode(query)}" if query else "")
    request = urllib.request.Request(url, headers={"Authorization": f"Bearer {TOKEN}"})
    try:
        return json.load(urllib.request.urlopen(request, timeout=60))
    except urllib.error.HTTPError as error:
        detail = json.loads(error.read() or b"{}").get("errors", [{}])[0]
        sys.exit(f"App Store Connect refused {path} ({error.code} {detail.get('code')}): {detail.get('detail')}")


def mb(n: float) -> str:
    return f"{n / 1_000_000:6.1f} MB"


app = get("/apps", **{"filter[bundleId]": os.environ["BUNDLE_ID"]})["data"]
if not app:
    sys.exit("No app with that bundle ID in App Store Connect.")
builds = get("/builds", **{"filter[app]": app[0]["id"], "sort": "-uploadedDate", "limit": LIMIT,
                           "include": "preReleaseVersion,buildBundles"})
included = builds.get("included", [])
versions = {v["id"]: v["attributes"]["version"] for v in included if v["type"] == "preReleaseVersions"}
bundles = {b["id"]: b["attributes"] for b in included if b["type"] == "buildBundles"}

print(f"{'version':8} {'build':>5}  {'download (median)':>17}  {'install (median)':>16}  "
      f"{'install (largest)':>17}  devices  reference iPhone")
for build in builds["data"]:
    attrs = build["attributes"]
    version = versions.get(build["relationships"]["preReleaseVersion"]["data"]["id"], "?")
    sizes = []
    for ref in build["relationships"].get("buildBundles", {}).get("data") or []:
        if bundles.get(ref["id"], {}).get("bundleType") not in (None, "APP"):
            continue
        sizes += [s["attributes"] for s in
                  get(f"/buildBundles/{ref['id']}/buildBundleFileSizes", limit=200)["data"]]
    if not sizes:
        print(f"{version:8} {attrs['version']:>5}  (no sizes yet: {attrs.get('processingState')})")
        continue
    downloads = [s["downloadBytes"] for s in sizes if s.get("downloadBytes")]
    installs = [s["installBytes"] for s in sizes if s.get("installBytes")]
    phones = sorted((s for s in sizes if str(s.get("deviceModel", "")).startswith("iPhone")),
                    key=lambda s: s.get("deviceModel", ""))
    ref = phones[-1] if phones else sizes[0]
    print(f"{version:8} {attrs['version']:>5}  {mb(statistics.median(downloads)):>17}  "
          f"{mb(statistics.median(installs)):>16}  {mb(max(installs)):>17}  {len(sizes):7}  "
          f"{ref.get('deviceModel')} iOS {ref.get('osVersion')}: "
          f"{mb(ref['downloadBytes']).strip()} down, {mb(ref['installBytes']).strip()} installed")
