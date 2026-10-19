"""App Store In-App Events (owner picks: "Draw someone new" 4A on 19 Oct 2026; Halloween
doodles, Streak week and Say it your way 2A 3A 4A the same day), made through the App
Store Connect API.

Idempotent: finds each event by its reference name, creates what's missing and fills only
events still editable (draft or rejected). MODE=draft stops there; MODE=submit sends every
editable event to App Review. Art: brand/appstore/event-<slug>-{card-1920x1080,details-1080x1920}.png.
Prints what it does, never keys. Reads ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8, BUNDLE_ID.
"""
import os
import sys
import time
import urllib.request

import release as R

# Required by Apple: opens Psst (home, where the features are).
DEEP_LINK = "psst://home"
ART = os.path.join(os.path.dirname(__file__), "..", "brand", "appstore")
EDITABLE = ("DRAFT", "READY_FOR_REVIEW", "REJECTED")

EVENTS = [
    {"reference": "Draw someone new (Oct 2026)", "slug": "draw-someone-new", "badge": "MAJOR_UPDATE",
     "purpose": "ATTRACT_NEW_USERS", "purchase": "NO_COST_ASSOCIATED",
     "publish": None, "start": None, "end": None,  # created 19 Oct: 21 Oct – 4 Nov
     "copy": {"name": "Draw someone new",
              "shortDescription": "Send a sealed doodle to someone new",
              "longDescription": "Draw with one finger and share it as a link. It stays sealed until they join Psst, "
                                 "then it's the first thing they see."}},
    {"reference": "Halloween doodles (Oct 2026)", "slug": "halloween-doodles", "badge": "SPECIAL_EVENT",
     "purpose": "ATTRACT_NEW_USERS", "purchase": "NO_COST_ASSOCIATED",
     "publish": "2026-10-23T16:00:00Z", "start": "2026-10-27T00:00:00Z", "end": "2026-11-01T23:59:00Z",
     "copy": {"name": "Halloween doodles",
              "shortDescription": "Draw them a ghost for their Home Screen",
              "longDescription": "Hold someone's band, draw a ghost, a pumpkin or a black cat, and it lands on their "
                                 "widget as a little polaroid. Free."}},
    {"reference": "Streak week (Nov 2026)", "slug": "streak-week", "badge": "CHALLENGE",
     "purpose": "KEEP_ACTIVE_USERS_INFORMED", "purchase": "NO_COST_ASSOCIATED",
     "publish": "2026-11-06T16:00:00Z", "start": "2026-11-10T16:00:00Z", "end": "2026-11-17T16:00:00Z",
     "copy": {"name": "Streak week",
              "shortDescription": "Psst every day and keep the flame going",
              "longDescription": "Psst each other every day for 7 days and a flame grows in the corner of their band. "
                                 "Miss a day and it starts again."}},
    {"reference": "Say it your way (Nov 2026)", "slug": "say-it-your-way", "badge": "MAJOR_UPDATE",
     "purpose": "KEEP_ACTIVE_USERS_INFORMED", "purchase": "IN_APP_PURCHASE",
     "publish": "2026-11-17T16:00:00Z", "start": "2026-11-20T16:00:00Z", "end": "2026-12-04T16:00:00Z",
     "copy": {"name": "Say it your way",
              "shortDescription": "Pick the word your people see",
              "longDescription": "With Psst+, your people see hey, boop, oi, yo, mwah or psst psst instead of psst. "
                                 "Pick yours once, for everyone."}},
]
IMAGES = {"EVENT_CARD": "card-1920x1080", "EVENT_DETAILS_PAGE": "details-1080x1920"}


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
    print(f"  Uploaded the {asset_type} image.")


def prepare(app: str, spec: dict, existing: dict, territories: list) -> str | None:
    """Creates or fills one event; returns its id when it's editable (ready to submit)."""
    for text, limit in ((spec["copy"]["name"], 30), (spec["copy"]["shortDescription"], 50),
                        (spec["copy"]["longDescription"], 120)):
        if len(text) > limit:
            sys.exit(f"{spec['reference']}: copy over {limit} characters: {text}")
    event = existing.get(spec["reference"])
    if event:
        state = event["attributes"].get("eventState")
        print(f"{spec['copy']['name']}: exists ({state}).")
        if state not in EDITABLE:
            return None
        if not event["attributes"].get("deepLink"):
            R.call("PATCH", f"/appEvents/{event['id']}", {"data": {
                "type": "appEvents", "id": event["id"], "attributes": {"deepLink": DEEP_LINK}}})
    else:
        if not spec["start"]:
            sys.exit(f"{spec['reference']} is missing and has no dates to create it with.")
        event = R.call("POST", "/appEvents", {"data": {
            "type": "appEvents",
            "attributes": {"referenceName": spec["reference"], "badge": spec["badge"], "primaryLocale": "en-US",
                           "deepLink": DEEP_LINK, "priority": "HIGH", "purpose": spec["purpose"],
                           "purchaseRequirement": spec["purchase"],
                           "territorySchedules": [{"territories": territories, "publishStart": spec["publish"],
                                                   "eventStart": spec["start"], "eventEnd": spec["end"]}]},
            "relationships": {"app": {"data": {"type": "apps", "id": app}}}}})["data"]
        print(f"{spec['copy']['name']}: created, {spec['start']} to {spec['end']}, {len(territories)} territories.")

    locs = R.call("GET", f"/appEvents/{event['id']}/localizations")["data"]
    loc = next((l for l in locs if l["attributes"].get("locale") == "en-US"), None)
    if loc:
        R.call("PATCH", f"/appEventLocalizations/{loc['id']}", {"data": {
            "type": "appEventLocalizations", "id": loc["id"], "attributes": spec["copy"]}})
    else:
        loc = R.call("POST", "/appEventLocalizations", {"data": {
            "type": "appEventLocalizations", "attributes": {"locale": "en-US", **spec["copy"]},
            "relationships": {"appEvent": {"data": {"type": "appEvents", "id": event["id"]}}}}})["data"]

    have = set()
    for shot in R.call("GET", f"/appEventLocalizations/{loc['id']}/appEventScreenshots")["data"]:
        state = (shot["attributes"].get("assetDeliveryState") or {}).get("state")
        if state in ("AWAITING_UPLOAD", "FAILED"):
            R.call("DELETE", f"/appEventScreenshots/{shot['id']}")  # a half-finished upload: start again
        else:
            have.add(shot["attributes"].get("appEventAssetType"))
    for asset_type, size in IMAGES.items():
        if asset_type not in have:
            upload(loc["id"], asset_type, os.path.join(ART, f"event-{spec['slug']}-{size}.png"))

    for _ in range(60):  # Apple must finish processing the images before review
        states = [(s["attributes"].get("assetDeliveryState") or {}).get("state")
                  for s in R.call("GET", f"/appEventLocalizations/{loc['id']}/appEventScreenshots")["data"]]
        if states and all(state == "COMPLETE" for state in states):
            break
        if "FAILED" in states:
            sys.exit(f"{spec['reference']}: Apple couldn't process an event image.")
        time.sleep(10)
    else:
        sys.exit(f"{spec['reference']}: images weren't processed within 10 minutes. Run again.")
    print(f"  Copy and images ready.")
    return event["id"]


def main():
    apps = R.call("GET", "/apps", **{"filter[bundleId]": os.environ["BUNDLE_ID"]})["data"]
    if not apps:
        sys.exit("No app with that bundle ID in App Store Connect.")
    app = apps[0]["id"]
    existing = {e["attributes"].get("referenceName"): e
                for e in R.call("GET", f"/apps/{app}/appEvents", limit="50")["data"]}
    territories = [t["id"] for t in R.call("GET", "/territories", limit="200")["data"]]
    ready = [i for spec in EVENTS if (i := prepare(app, spec, existing, territories))]

    if os.environ.get("MODE", "draft") != "submit" or not ready:
        print(f"{len(ready)} event(s) ready as drafts. Not submitted." if ready else "Nothing to submit.")
        return
    open_ones = R.call("GET", "/reviewSubmissions", **{"filter[app]": app, "filter[platform]": "IOS",
                                                       "filter[state]": "READY_FOR_REVIEW"})["data"]
    submission = open_ones[0] if open_ones else R.call("POST", "/reviewSubmissions", {"data": {
        "type": "reviewSubmissions", "attributes": {"platform": "IOS"},
        "relationships": {"app": {"data": {"type": "apps", "id": app}}}}})["data"]
    for event_id in ready:
        R.call("POST", "/reviewSubmissionItems", {"data": {
            "type": "reviewSubmissionItems", "relationships": {
                "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": submission["id"]}},
                "appEvent": {"data": {"type": "appEvents", "id": event_id}}}}})
    R.call("PATCH", f"/reviewSubmissions/{submission['id']}", {"data": {
        "type": "reviewSubmissions", "id": submission["id"], "attributes": {"submitted": True}}})
    print(f"Submitted {len(ready)} event(s) for review.")


if __name__ == "__main__":
    main()
