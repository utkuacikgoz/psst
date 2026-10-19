"""Puts a build up for App Store review through the App Store Connect API.

Takes VERSION (e.g. 1.0.7), BUILD (e.g. 37) and MODE ("prepare", "submit" or "promo").
The store listings (name, subtitle, keywords, promotional text, description) come
from docs/ASO.md, one section per language, adding store pages that don't exist
yet. MODE=promo only sets the promotional text, on the live version and any
version in review, and needs no VERSION or BUILD.
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
ASO = os.path.join(os.path.dirname(__file__), "..", "docs", "ASO.md")
SHOTS = os.path.join(os.path.dirname(__file__), "..", "brand", "appstore")
# Apple's APP_IPHONE_67 set takes 1290x2796 (custom product pages refuse 1320x2868 there
# with SPEC_MISMATCH); APP_IPHONE_65 takes 1284x2778. The 1320x2868 originals stay as masters.
DISPLAY = {"1290x2796": "APP_IPHONE_67", "1284x2778": "APP_IPHONE_65"}


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
        # Apple puts the reasons a resource can't be reviewed in meta.associatedErrors.
        for e in errors:
            for path, nested in ((e.get("meta") or {}).get("associatedErrors") or {}).items():
                detail += "".join(f"; {path}: {n.get('code')}: {n.get('detail')}" for n in nested)
        hint = " (the API key needs the App Manager or Admin role)" if error.code == 403 else ""
        sys.exit(f"App Store Connect refused {method} {path} ({error.code}) {detail}{hint}")


def section(version: str) -> tuple[str, str, dict[str, str]]:
    text = open(NOTES, encoding="utf-8").read()
    match = re.search(rf"^## {re.escape(version)} \(.*?(?=^## |\Z)", text, re.M | re.S)
    if not match:
        sys.exit(f"docs/APP_REVIEW_NOTES.md has no '## {version} (' section.")
    body = match.group(0)

    def block(title: str, required=True) -> str | None:
        found = re.search(rf"\*\*{re.escape(title)}\*\*\s*```\n(.*?)\n```", body, re.S)
        if not found:
            if not required:
                return None
            sys.exit(f"The {version} section has no '{title}' block.")
        return found.group(1).strip()

    # Optional: the main language's store description and promotional text.
    store = {key: found_text for key, title in (("description", "Description:"), ("promotionalText", "Promotional text:"))
             if (found_text := block(title, required=False))}
    return block("What's New in This Version:"), block("Notes for the reviewer:"), store


def listings() -> dict[str, dict[str, str]]:
    """Every store listing in docs/ASO.md, by locale ("## en-US · English (U.S.) — primary")."""
    text = open(ASO, encoding="utf-8").read()
    limits = {"name": 30, "subtitle": 30, "keywords": 100, "promotionalText": 170, "description": 4000}
    found: dict[str, dict[str, str]] = {}
    for match in re.finditer(r"^## ([a-z]{2}(?:-[A-Z]{2})?) · .*?(?=^## |\Z)", text, re.M | re.S):
        body, fields = match.group(0), {}
        for key, label in (("name", "Name"), ("subtitle", "Subtitle"), ("keywords", "Keywords"),
                           ("promotionalText", "Promotional text")):
            line = re.search(rf"^- \*\*{label} \(\d+/\d+\):\*\* `?(.+?)`?$", body, re.M)
            if line:
                fields[key] = line.group(1).strip()
        description = re.search(r"\*\*Description:\*\*\s*```\n(.*?)\n```", body, re.S)
        if description:
            fields["description"] = description.group(1).strip()
        for key, value in fields.items():
            if len(value) > limits[key]:
                sys.exit(f"docs/ASO.md {match.group(1)}: {key} is {len(value)} characters; the limit is {limits[key]}.")
        found[match.group(1)] = fields
    if not found:
        sys.exit("docs/ASO.md has no '## <locale> · ' listings.")
    return found


def version_localization(version_id: str, locale: str, existing: list[dict], whats_new: str) -> dict:
    """The version's localization for this locale, added if the store page doesn't have it yet."""
    loc = next((l for l in existing if l["attributes"].get("locale") == locale), None)
    if loc:
        return loc
    loc = call("POST", "/appStoreVersionLocalizations", {"data": {
        "type": "appStoreVersionLocalizations", "attributes": {"locale": locale, "whatsNew": whats_new},
        "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}}}}})["data"]
    print(f"Added the {locale} store page.")
    existing.append(loc)
    return loc


def set_promotional_text(app: str, texts: dict[str, str]):
    """Promotional text can change at any time, without review: every language the page has."""
    live = ("READY_FOR_SALE", "PREPARE_FOR_SUBMISSION", "WAITING_FOR_REVIEW", "IN_REVIEW", "PENDING_DEVELOPER_RELEASE")
    versions = call("GET", f"/apps/{app}/appStoreVersions", **{"filter[platform]": "IOS", "limit": "10"})["data"]
    for version in versions:
        state = version["attributes"].get("appStoreState")
        if state not in live:
            continue
        for loc in call("GET", f"/appStoreVersions/{version['id']}/appStoreVersionLocalizations")["data"]:
            locale = loc["attributes"].get("locale")
            if locale not in texts:
                continue
            try:
                call("PATCH", f"/appStoreVersionLocalizations/{loc['id']}", {"data": {
                    "type": "appStoreVersionLocalizations", "id": loc["id"],
                    "attributes": {"promotionalText": texts[locale]}}})
                print(f"Promotional text set on {version['attributes'].get('versionString')} ({state}, {locale}).")
            except SystemExit as refused:
                print(f"Not set on {version['attributes'].get('versionString')} ({state}, {locale}): {refused}")


def set_names_and_subtitles(app: str, store: dict[str, dict[str, str]]):
    """Name and subtitle live on the App Information that's still editable (the next version's)."""
    infos = call("GET", f"/apps/{app}/appInfos")["data"]
    editable = [i for i in infos if (i["attributes"].get("appStoreState") or i["attributes"].get("state"))
                not in ("READY_FOR_SALE", "READY_FOR_DISTRIBUTION", "WAITING_FOR_REVIEW", "IN_REVIEW")]
    if not editable:
        print("Names and subtitles not changed: no editable App Information (a version is in review).")
        return
    info = editable[0]["id"]
    locs = call("GET", f"/appInfos/{info}/appInfoLocalizations")["data"]
    for locale, fields in store.items():
        attributes = {k: fields[k] for k in ("name", "subtitle") if k in fields}
        if not attributes:
            continue
        loc = next((l for l in locs if l["attributes"].get("locale") == locale), None)
        if loc:
            call("PATCH", f"/appInfoLocalizations/{loc['id']}", {"data": {
                "type": "appInfoLocalizations", "id": loc["id"], "attributes": attributes}})
        else:
            call("POST", "/appInfoLocalizations", {"data": {
                "type": "appInfoLocalizations",
                "attributes": {"locale": locale, "privacyPolicyUrl": "https://psstapp.fun/privacy", **attributes},
                "relationships": {"appInfo": {"data": {"type": "appInfos", "id": info}}}}})
        print(f"Name and subtitle set ({locale}).")


def screenshot_files() -> dict[str, list[str]]:
    """brand/appstore's "<n>-<name>-<w>x<h>.png" files by display type, in their numbered order."""
    found: dict[str, list[str]] = {}
    for name in sorted(os.listdir(SHOTS), key=lambda n: (int(n.split("-")[0]) if n.split("-")[0].isdigit() else 99, n)):
        match = re.match(r"\d+-.+-(\d+x\d+)\.png$", name)
        if match and match.group(1) in DISPLAY:
            found.setdefault(DISPLAY[match.group(1)], []).append(os.path.join(SHOTS, name))
    return found


def replace_screenshots(localization: str, display: str, files: list[str], wait=time.sleep,
                        parent: str = "appStoreVersionLocalization"):
    """Empties (or makes) the localization's screenshot set for this display, uploads the files
    in order through Apple's upload operations, and waits until Apple has processed them.
    parent is "appStoreVersionLocalization", or "appCustomProductPageLocalization" for a
    custom product page."""
    sets = call("GET", f"/{parent}s/{localization}/appScreenshotSets",
                **{"filter[screenshotDisplayType]": display})["data"]
    if sets:
        set_id = sets[0]["id"]
        for old in call("GET", f"/appScreenshotSets/{set_id}/appScreenshots")["data"]:
            call("DELETE", f"/appScreenshots/{old['id']}")
    else:
        set_id = call("POST", "/appScreenshotSets", {"data": {
            "type": "appScreenshotSets", "attributes": {"screenshotDisplayType": display},
            "relationships": {parent: {"data": {"type": f"{parent}s", "id": localization}}}}})["data"]["id"]
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
        delivery = [call("GET", f"/appScreenshots/{i}")["data"]["attributes"].get("assetDeliveryState") or {}
                    for i in ids]
        states = [d.get("state") for d in delivery]
        if "FAILED" in states:
            reasons = "; ".join(f"{os.path.basename(files[n])}: {e.get('code')} {e.get('description')}"
                                for n, d in enumerate(delivery) if d.get("state") == "FAILED" for e in d.get("errors") or [{}])
            sys.exit(f"Apple couldn't process a {display} screenshot: {reasons}")
        if all(state == "COMPLETE" for state in states):
            print(f"Screenshots set: {len(ids)} for {display}.")
            return
        wait(10)
    sys.exit(f"The {display} screenshots weren't processed within 10 minutes. Try again.")


def main():
    mode = os.environ.get("MODE", "prepare")
    stores = listings()
    if mode == "promo":
        apps = call("GET", "/apps", **{"filter[bundleId]": os.environ["BUNDLE_ID"]})["data"]
        if not apps:
            sys.exit("No app with that bundle ID in App Store Connect.")
        set_promotional_text(apps[0]["id"], {l: f["promotionalText"] for l, f in stores.items() if "promotionalText" in f})
        return
    version, build_number = os.environ["VERSION"].strip(), os.environ["BUILD"].strip()
    submit = mode == "submit"
    whats_new, notes, store_text = section(version)
    # A version section's own description / promotional text win over docs/ASO.md's (main language).
    overrides = store_text
    if len(whats_new) > 4000 or len(notes) > 4000 or len(overrides.get("description", "")) > 4000:
        sys.exit("What's New, the description and the review notes must each be 4,000 characters or fewer.")
    if len(overrides.get("promotionalText", "")) > 170:
        sys.exit("The promotional text must be 170 characters or fewer.")

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

    primary = call("GET", f"/apps/{app}")["data"]["attributes"].get("primaryLocale")
    for locale, fields in stores.items():
        text = {k: v for k, v in fields.items() if k in ("description", "promotionalText", "keywords")}
        if locale == primary:
            text.update(overrides)
        if text:
            loc = version_localization(vid, locale, localizations, whats_new)
            call("PATCH", f"/appStoreVersionLocalizations/{loc['id']}", {"data": {
                "type": "appStoreVersionLocalizations", "id": loc["id"], "attributes": text}})
            print(f"Set {' and '.join(sorted(text))} ({locale}).")
    set_names_and_subtitles(app, stores)
    main_loc = next((l for l in localizations if l["attributes"].get("locale") == primary), localizations[0])
    if os.environ.get("SCREENSHOTS", "upload") != "keep":
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
