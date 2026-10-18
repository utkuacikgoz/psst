"""Puts a build up for App Store review through the App Store Connect API.

Takes VERSION (e.g. 1.0.7), BUILD (e.g. 37) and MODE ("prepare" or "submit").
Reads What's New and the reviewer notes from that version's section in
docs/APP_REVIEW_NOTES.md ("## 1.0.7 (...)"), then: creates the App Store version
if needed, attaches the build, fills What's New in every localization and the
review notes, replaces the App Store screenshots with brand/appstore (unless
SCREENSHOTS=keep), and with MODE=submit sends it for review. Prints what it does,
never keys. Reads ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8 and BUNDLE_ID.
"""
import hashlib
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import jwt

API = "https://api.appstoreconnect.apple.com/v1"
NOTES = os.path.join(os.path.dirname(__file__), "..", "docs", "APP_REVIEW_NOTES.md")
SHOTS = os.path.join(os.path.dirname(__file__), "..", "brand", "appstore")
# 6.9" screenshots go in Apple's APP_IPHONE_67 set; 6.5" in APP_IPHONE_65.
DISPLAY = {"1320x2868": "APP_IPHONE_67", "1284x2778": "APP_IPHONE_65"}


def key() -> str:
    body = "".join(l for l in os.environ["ASC_KEY_P8"].splitlines() if "-----" not in l)
    body = "".join(body.split())
    lines = "\n".join(body[i:i + 64] for i in range(0, len(body), 64))
    return f"-----BEGIN PRIVATE KEY-----\n{lines}\n-----END PRIVATE KEY-----\n"


def token() -> str:
    now = int(time.time())
    return jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"},
                      key(), algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})


TOKEN = None


def call(method: str, path: str, body: dict | None = None, **query) -> dict:
    global TOKEN
    TOKEN = TOKEN or token()
    url = f"{API}{path}" + (f"?{urllib.parse.urlencode(query)}" if query else "")
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(url, data=data, method=method, headers={
        "Authorization": f"Bearer {TOKEN}", "Content-Type": "application/json"})
    try:
        raw = urllib.request.urlopen(request, timeout=60).read()
        return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as error:
        errors = json.loads(error.read() or b"{}").get("errors", [{}])
        detail = "; ".join(f"{e.get('code')}: {e.get('detail')}" for e in errors)
        hint = " (the API key needs the App Manager or Admin role)" if error.code == 403 else ""
        sys.exit(f"App Store Connect refused {method} {path} ({error.code}) {detail}{hint}")


def section(version: str) -> tuple[str, str]:
    text = open(NOTES, encoding="utf-8").read()
    match = re.search(rf"^## {re.escape(version)} \(.*?(?=^## |\Z)", text, re.M | re.S)
    if not match:
        sys.exit(f"docs/APP_REVIEW_NOTES.md has no '## {version} (' section.")
    body = match.group(0)

    def block(title: str) -> str:
        found = re.search(rf"\*\*{re.escape(title)}\*\*\s*```\n(.*?)\n```", body, re.S)
        if not found:
            sys.exit(f"The {version} section has no '{title}' block.")
        return found.group(1).strip()

    return block("What's New in This Version:"), block("Notes for the reviewer:")


def screenshot_files() -> dict[str, list[str]]:
    """brand/appstore's "<n>-<name>-<w>x<h>.png" files by display type, in their numbered order."""
    found: dict[str, list[str]] = {}
    for name in sorted(os.listdir(SHOTS), key=lambda n: (int(n.split("-")[0]) if n.split("-")[0].isdigit() else 99, n)):
        match = re.match(r"\d+-.+-(\d+x\d+)\.png$", name)
        if match and match.group(1) in DISPLAY:
            found.setdefault(DISPLAY[match.group(1)], []).append(os.path.join(SHOTS, name))
    return found


def replace_screenshots(localization: str, display: str, files: list[str], wait=time.sleep):
    """Empties (or makes) the localization's screenshot set for this display, uploads the files
    in order through Apple's upload operations, and waits until Apple has processed them."""
    sets = call("GET", f"/appStoreVersionLocalizations/{localization}/appScreenshotSets",
                **{"filter[screenshotDisplayType]": display})["data"]
    if sets:
        set_id = sets[0]["id"]
        for old in call("GET", f"/appScreenshotSets/{set_id}/appScreenshots")["data"]:
            call("DELETE", f"/appScreenshots/{old['id']}")
    else:
        set_id = call("POST", "/appScreenshotSets", {"data": {
            "type": "appScreenshotSets", "attributes": {"screenshotDisplayType": display},
            "relationships": {"appStoreVersionLocalization": {
                "data": {"type": "appStoreVersionLocalizations", "id": localization}}}}})["data"]["id"]
    ids = []
    for path in files:
        data = open(path, "rb").read()
        shot = call("POST", "/appScreenshots", {"data": {
            "type": "appScreenshots", "attributes": {"fileName": os.path.basename(path), "fileSize": len(data)},
            "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}}}})["data"]
        for op in shot["attributes"]["uploadOperations"]:
            part = data[op["offset"]:op["offset"] + op["length"]]
            headers = {h["name"]: h["value"] for h in op.get("requestHeaders") or []}
            urllib.request.urlopen(urllib.request.Request(op["url"], data=part, method=op["method"],
                                                          headers=headers), timeout=120).read()
        call("PATCH", f"/appScreenshots/{shot['id']}", {"data": {
            "type": "appScreenshots", "id": shot["id"],
            "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})
        ids.append(shot["id"])
    call("PATCH", f"/appScreenshotSets/{set_id}/relationships/appScreenshots",
         {"data": [{"type": "appScreenshots", "id": i} for i in ids]})
    for _ in range(60):
        states = [call("GET", f"/appScreenshots/{i}")["data"]["attributes"].get("assetDeliveryState", {}).get("state")
                  for i in ids]
        if "FAILED" in states:
            sys.exit(f"Apple couldn't process a {display} screenshot.")
        if all(state == "COMPLETE" for state in states):
            print(f"Screenshots set: {len(ids)} for {display}.")
            return
        wait(10)
    sys.exit(f"The {display} screenshots weren't processed within 10 minutes. Try again.")


def main():
    version, build_number = os.environ["VERSION"].strip(), os.environ["BUILD"].strip()
    submit = os.environ.get("MODE", "prepare") == "submit"
    whats_new, notes = section(version)
    if len(whats_new) > 4000 or len(notes) > 4000:
        sys.exit("What's New and the review notes must each be 4,000 characters or fewer.")

    apps = call("GET", "/apps", **{"filter[bundleId]": os.environ["BUNDLE_ID"]})["data"]
    if not apps:
        sys.exit("No app with that bundle ID in App Store Connect.")
    app = apps[0]["id"]

    builds = call("GET", "/builds", **{"filter[app]": app, "filter[version]": build_number,
                                       "filter[preReleaseVersion.version]": version})["data"]
    if not builds:
        sys.exit(f"No build {build_number} for version {version}. Is it uploaded and is the version right?")
    build = builds[0]
    state = build["attributes"].get("processingState")
    if state != "VALID":
        sys.exit(f"Build {build_number} is {state}, not VALID yet. Try again when Apple has processed it.")
    print(f"Build {build_number} ({version}) is processed.")

    versions = call("GET", f"/apps/{app}/appStoreVersions",
                    **{"filter[versionString]": version, "filter[platform]": "IOS"})["data"]
    if versions:
        store_version = versions[0]
        print(f"App Store version {version} exists ({store_version['attributes'].get('appStoreState')}).")
    else:
        store_version = call("POST", "/appStoreVersions", {"data": {
            "type": "appStoreVersions", "attributes": {"platform": "IOS", "versionString": version},
            "relationships": {"app": {"data": {"type": "apps", "id": app}}}}})["data"]
        print(f"Created App Store version {version}.")
    vid = store_version["id"]

    call("PATCH", f"/appStoreVersions/{vid}/relationships/build", {"data": {"type": "builds", "id": build["id"]}})
    print(f"Attached build {build_number}.")

    localizations = call("GET", f"/appStoreVersions/{vid}/appStoreVersionLocalizations")["data"]
    for localization in localizations:
        call("PATCH", f"/appStoreVersionLocalizations/{localization['id']}", {"data": {
            "type": "appStoreVersionLocalizations", "id": localization["id"], "attributes": {"whatsNew": whats_new}}})
        print(f"What's New set ({localization['attributes'].get('locale')}).")

    if os.environ.get("SCREENSHOTS", "upload") != "keep":
        primary = call("GET", f"/apps/{app}")["data"]["attributes"].get("primaryLocale")
        main_loc = next((l for l in localizations if l["attributes"].get("locale") == primary), localizations[0])
        for display, files in screenshot_files().items():
            replace_screenshots(main_loc["id"], display, files)
        for other in localizations:
            if other["id"] != main_loc["id"] and call(
                    "GET", f"/appStoreVersionLocalizations/{other['id']}/appScreenshotSets")["data"]:
                print(f"Note: {other['attributes'].get('locale')} has its own screenshots and keeps them.")

    detail = call("GET", f"/appStoreVersions/{vid}/appStoreReviewDetail").get("data")
    if detail:
        call("PATCH", f"/appStoreReviewDetails/{detail['id']}", {"data": {
            "type": "appStoreReviewDetails", "id": detail["id"], "attributes": {"notes": notes}}})
    else:
        sys.exit("This version has no App Review contact details yet. Fill them in once in App Store Connect, "
                 "then run again.")
    print("Review notes set.")

    if not submit:
        print(f"Prepared {version} with build {build_number}. Not submitted (MODE=prepare).")
        return

    open_states = "READY_FOR_REVIEW,WAITING_FOR_REVIEW,IN_REVIEW,UNRESOLVED_ISSUES"
    existing = call("GET", "/reviewSubmissions", **{"filter[app]": app, "filter[platform]": "IOS",
                                                    "filter[state]": open_states})["data"]
    if any(s["attributes"].get("state") in ("WAITING_FOR_REVIEW", "IN_REVIEW") for s in existing):
        sys.exit("Something is already waiting for or in review. Nothing submitted.")
    submission = next((s for s in existing if s["attributes"].get("state") == "READY_FOR_REVIEW"), None)
    if not submission:
        submission = call("POST", "/reviewSubmissions", {"data": {
            "type": "reviewSubmissions", "attributes": {"platform": "IOS"},
            "relationships": {"app": {"data": {"type": "apps", "id": app}}}}})["data"]
    call("POST", "/reviewSubmissionItems", {"data": {
        "type": "reviewSubmissionItems", "relationships": {
            "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": submission["id"]}},
            "appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}})
    call("PATCH", f"/reviewSubmissions/{submission['id']}", {"data": {
        "type": "reviewSubmissions", "id": submission["id"], "attributes": {"submitted": True}}})
    print(f"Submitted {version} (build {build_number}) for App Review.")


if __name__ == "__main__":
    main()
