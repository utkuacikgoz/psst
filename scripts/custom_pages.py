"""Custom product pages (owner go, 19 Oct 2026): one App Store page per landing page
on psstapp.fun, each opening on the screenshot that matches it. Same seven approved
screenshots (brand/appstore), reordered; the landing pages link to them with ?ppid=.

Idempotent: finds each page by name, (re)fills its screenshots and promotional text.
MODE=draft stops there; MODE=submit sends the pages to App Review. Prints each page's
ppid and URL. Reads ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8, BUNDLE_ID.
"""
import os
import sys

import release as R

# Screenshot numbers (brand/appstore/<n>-*.png) in the order each page shows them.
PAGES = {
    "Doodle widget": ([2, 4, 1, 3, 5, 6, 7],
                      "Draw something with one finger and it lands on their Home Screen as a little polaroid. Free, just for your people."),
    "Long distance": ([1, 3, 5, 2, 4, 6, 7],
                      "Close, from far away: one tap says thinking of you, doodles land on their Home Screen, streaks keep you close."),
    "Couples widget": ([2, 3, 5, 1, 4, 6, 7],
                       "A widget for the two of you: their doodles on your Home Screen and a one-tap Psst from the Lock Screen."),
    "Remember Yo": ([1, 6, 3, 2, 4, 5, 7],
                    "One tap that says thinking of you, just for the people you invite. With Psst+, your word can even be yo."),
}


def files_in_order(order: list[int]) -> dict[str, list[str]]:
    by_display = R.screenshot_files()
    out = {}
    for display, files in by_display.items():
        by_number = {int(os.path.basename(f).split("-")[0]): f for f in files}
        out[display] = [by_number[n] for n in order]
    return out


def main():
    for name, (_, promo) in PAGES.items():
        if len(promo) > 170:
            sys.exit(f"{name}: promotional text is {len(promo)} characters; the limit is 170.")
    apps = R.call("GET", "/apps", **{"filter[bundleId]": os.environ["BUNDLE_ID"]})["data"]
    if not apps:
        sys.exit("No app with that bundle ID in App Store Connect.")
    app = apps[0]["id"]
    primary = R.call("GET", f"/apps/{app}")["data"]["attributes"].get("primaryLocale") or "en-US"
    existing = {p["attributes"].get("name"): p for p in
                R.call("GET", f"/apps/{app}/appCustomProductPages", limit="50")["data"]}
    versions_to_submit = []
    for name, (order, promo) in PAGES.items():
        page = existing.get(name)
        if not page:
            page = R.call("POST", "/appCustomProductPages", {
                "data": {"type": "appCustomProductPages", "attributes": {"name": name},
                         "relationships": {
                             "app": {"data": {"type": "apps", "id": app}},
                             "appCustomProductPageVersions": {"data": [{"type": "appCustomProductPageVersions",
                                                                         "id": "${version}"}]}}},
                "included": [
                    {"type": "appCustomProductPageVersions", "id": "${version}",
                     "relationships": {"appCustomProductPageLocalizations": {
                         "data": [{"type": "appCustomProductPageLocalizations", "id": "${localization}"}]}}},
                    {"type": "appCustomProductPageLocalizations", "id": "${localization}",
                     "attributes": {"locale": primary, "promotionalText": promo}}]})["data"]
            print(f"Created the custom product page '{name}'.")
        versions = R.call("GET", f"/appCustomProductPages/{page['id']}/appCustomProductPageVersions")["data"]
        version = next((v for v in versions if v["attributes"].get("state") in
                        ("PREPARE_FOR_SUBMISSION", "READY_FOR_REVIEW", "REJECTED")), None)
        if not version:
            print(f"'{name}' has nothing to edit ({', '.join(v['attributes'].get('state', '?') for v in versions)}).")
        else:
            locs = R.call("GET", f"/appCustomProductPageVersions/{version['id']}/appCustomProductPageLocalizations")["data"]
            loc = next((l for l in locs if l["attributes"].get("locale") == primary), locs[0])
            R.call("PATCH", f"/appCustomProductPageLocalizations/{loc['id']}", {"data": {
                "type": "appCustomProductPageLocalizations", "id": loc["id"], "attributes": {"promotionalText": promo}}})
            # Only the 6.5" set: Apple refused every 6.9" file on custom pages (SPEC_MISMATCH, 19 Oct
            # 2026) though the same files are fine on the main page; 6.5" covers every iPhone.
            for old in R.call("GET", f"/appCustomProductPageLocalizations/{loc['id']}/appScreenshotSets",
                              **{"filter[screenshotDisplayType]": "APP_IPHONE_67"})["data"]:
                R.call("DELETE", f"/appScreenshotSets/{old['id']}")
            for display, files in files_in_order(order).items():
                if display == "APP_IPHONE_65":
                    R.replace_screenshots(loc["id"], display, files, parent="appCustomProductPageLocalization")
            versions_to_submit.append(version["id"])
        print(f"'{name}': ppid={page['id']} url={page['attributes'].get('url')}")

    if os.environ.get("MODE", "draft") != "submit" or not versions_to_submit:
        print("Pages ready. Not submitted (MODE=draft)." if versions_to_submit else "Nothing to submit.")
        return
    open_ones = R.call("GET", "/reviewSubmissions", **{"filter[app]": app, "filter[platform]": "IOS",
                                                       "filter[state]": "READY_FOR_REVIEW"})["data"]
    submission = open_ones[0] if open_ones else R.call("POST", "/reviewSubmissions", {"data": {
        "type": "reviewSubmissions", "attributes": {"platform": "IOS"},
        "relationships": {"app": {"data": {"type": "apps", "id": app}}}}})["data"]
    for version_id in versions_to_submit:
        R.call("POST", "/reviewSubmissionItems", {"data": {
            "type": "reviewSubmissionItems", "relationships": {
                "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": submission["id"]}},
                "appCustomProductPageVersion": {"data": {"type": "appCustomProductPageVersions", "id": version_id}}}}})
    R.call("PATCH", f"/reviewSubmissions/{submission['id']}", {"data": {
        "type": "reviewSubmissions", "id": submission["id"], "attributes": {"submitted": True}}})
    print(f"Submitted {len(versions_to_submit)} custom product pages for review.")


if __name__ == "__main__":
    main()
