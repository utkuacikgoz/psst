"""Creates (and with MODE=submit, sends for review) the App Store In-App Event
"Draw someone new" (owner pick 4A, 19 Oct 2026) through the App Store Connect API.

Idempotent: finds the event by its reference name and only fills what's missing.
Runs 14 days from START (default: two days from now, so Apple can review first).
Images: brand/appstore/event-draw-someone-new-{card-1920x1080,details-1080x1920}.png.
Prints what it does, never keys. Reads ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8, BUNDLE_ID.
"""
import datetime
import os
import sys
import time
import urllib.request

import release as R

REFERENCE = "Draw someone new (Oct 2026)"
# Required by Apple: opens Psst (home, where + leads to Draw someone new).
DEEP_LINK = "psst://home"
COPY = {"name": "Draw someone new",
        "shortDescription": "Send a sealed doodle to someone new",
        "longDescription": "Draw with one finger and share it as a link. It stays sealed until they join Psst, "
                           "then it's the first thing they see."}
ART = os.path.join(os.path.dirname(__file__), "..", "brand", "appstore")
IMAGES = {"EVENT_CARD": "event-draw-someone-new-card-1920x1080.png",
          "EVENT_DETAILS_PAGE": "event-draw-someone-new-details-1080x1920.png"}


def upload(localization: str, asset_type: str, path: str):
    data = open(path, "rb").read()
    shot = R.call("POST", "/appEventScreenshots", {"data": {
        "type": "appEventScreenshots",
        "attributes": {"fileName": os.path.basename(path), "fileSize": len(data), "appEventAssetType": asset_type},
        "relationships": {"appEventLocalization": {"data": {"type": "appEventLocalizations", "id": localization}}}}})["data"]
    for op in shot["attributes"]["uploadOperations"]:
        part = data[op["offset"]:op["offset"] + op["length"]]
        headers = {h["name"]: h["value"] for h in op.get("requestHeaders") or []}
        urllib.request.urlopen(urllib.request.Request(op["url"], data=part, method=op["method"], headers=headers),
                               timeout=120).read()
    # Unlike app screenshots, event images take no checksum.
    R.call("PATCH", f"/appEventScreenshots/{shot['id']}", {"data": {
        "type": "appEventScreenshots", "id": shot["id"], "attributes": {"uploaded": True}}})
    print(f"Uploaded the {asset_type} image.")


def main():
    for text, limit in ((COPY["name"], 30), (COPY["shortDescription"], 50), (COPY["longDescription"], 120)):
        if len(text) > limit:
            sys.exit(f"Event copy over {limit} characters: {text}")
    apps = R.call("GET", "/apps", **{"filter[bundleId]": os.environ["BUNDLE_ID"]})["data"]
    if not apps:
        sys.exit("No app with that bundle ID in App Store Connect.")
    app = apps[0]["id"]

    events = R.call("GET", f"/apps/{app}/appEvents", limit="50")["data"]
    event = next((e for e in events if e["attributes"].get("referenceName") == REFERENCE), None)
    if event:
        print(f"Event exists ({event['attributes'].get('eventState')}).")
        if not event["attributes"].get("deepLink"):
            R.call("PATCH", f"/appEvents/{event['id']}", {"data": {
                "type": "appEvents", "id": event["id"], "attributes": {"deepLink": DEEP_LINK}}})
            print(f"Deep link set: {DEEP_LINK}.")
    else:
        start = os.environ.get("START") or (datetime.datetime.now(datetime.timezone.utc)
                                            + datetime.timedelta(days=2)).strftime("%Y-%m-%dT16:00:00Z")
        begin = datetime.datetime.fromisoformat(start.replace("Z", "+00:00"))
        end = (begin + datetime.timedelta(days=14)).strftime("%Y-%m-%dT%H:%M:%SZ")
        territories = [t["id"] for t in R.call("GET", "/territories", limit="200")["data"]]
        event = R.call("POST", "/appEvents", {"data": {
            "type": "appEvents",
            "attributes": {"referenceName": REFERENCE, "badge": "MAJOR_UPDATE", "primaryLocale": "en-US",
                           "deepLink": DEEP_LINK,
                           "priority": "HIGH", "purpose": "ATTRACT_NEW_USERS",
                           "purchaseRequirement": "NO_COST_ASSOCIATED",
                           "territorySchedules": [{"territories": territories, "publishStart": start,
                                                   "eventStart": start, "eventEnd": end}]},
            "relationships": {"app": {"data": {"type": "apps", "id": app}}}}})["data"]
        print(f"Created the event: {start} to {end}, {len(territories)} territories.")

    locs = R.call("GET", f"/appEvents/{event['id']}/localizations")["data"]
    loc = next((l for l in locs if l["attributes"].get("locale") == "en-US"), None)
    if loc:
        R.call("PATCH", f"/appEventLocalizations/{loc['id']}", {"data": {
            "type": "appEventLocalizations", "id": loc["id"], "attributes": COPY}})
    else:
        loc = R.call("POST", "/appEventLocalizations", {"data": {
            "type": "appEventLocalizations", "attributes": {"locale": "en-US", **COPY},
            "relationships": {"appEvent": {"data": {"type": "appEvents", "id": event["id"]}}}}})["data"]
    print("Event name and descriptions set (en-US).")

    have = set()
    for shot in R.call("GET", f"/appEventLocalizations/{loc['id']}/appEventScreenshots")["data"]:
        state = (shot["attributes"].get("assetDeliveryState") or {}).get("state")
        if state in ("AWAITING_UPLOAD", "FAILED"):
            R.call("DELETE", f"/appEventScreenshots/{shot['id']}")  # a half-finished upload: start again
        else:
            have.add(shot["attributes"].get("appEventAssetType"))
    for asset_type, name in IMAGES.items():
        if asset_type not in have:
            upload(loc["id"], asset_type, os.path.join(ART, name))

    for _ in range(60):  # Apple must finish processing the images before review
        states = [(s["attributes"].get("assetDeliveryState") or {}).get("state")
                  for s in R.call("GET", f"/appEventLocalizations/{loc['id']}/appEventScreenshots")["data"]]
        if states and all(state == "COMPLETE" for state in states):
            print("Event images processed.")
            break
        if "FAILED" in states:
            sys.exit("Apple couldn't process an event image.")
        time.sleep(10)
    else:
        sys.exit("Event images weren't processed within 10 minutes. Run again.")

    if os.environ.get("MODE", "draft") != "submit":
        print("Event ready as a draft. Not submitted (MODE=draft).")
        return
    open_ones = R.call("GET", "/reviewSubmissions", **{"filter[app]": app, "filter[platform]": "IOS",
                                                       "filter[state]": "READY_FOR_REVIEW"})["data"]
    submission = open_ones[0] if open_ones else R.call("POST", "/reviewSubmissions", {"data": {
        "type": "reviewSubmissions", "attributes": {"platform": "IOS"},
        "relationships": {"app": {"data": {"type": "apps", "id": app}}}}})["data"]
    R.call("POST", "/reviewSubmissionItems", {"data": {
        "type": "reviewSubmissionItems", "relationships": {
            "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": submission["id"]}},
            "appEvent": {"data": {"type": "appEvents", "id": event["id"]}}}}})
    R.call("PATCH", f"/reviewSubmissions/{submission['id']}", {"data": {
        "type": "reviewSubmissions", "id": submission["id"], "attributes": {"submitted": True}}})
    print("Event submitted for review.")


if __name__ == "__main__":
    main()
