"""Read-only: what's waiting for or in App Review (submissions, their items), the
App Store versions and the In-App Events, so a blocked submit can be explained.
Prints states only, never keys. Reads ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8, BUNDLE_ID."""
import os
import sys

import release as R


def main():
    apps = R.call("GET", "/apps", **{"filter[bundleId]": os.environ["BUNDLE_ID"]})["data"]
    if not apps:
        sys.exit("No app with that bundle ID in App Store Connect.")
    app = apps[0]["id"]

    print("Review submissions (newest first):")
    subs = R.call("GET", "/reviewSubmissions", **{"filter[app]": app, "filter[platform]": "IOS", "limit": "20",
                                                  "include": "items"})
    for sub in subs["data"]:
        a = sub["attributes"]
        if a.get("state") in ("COMPLETE",):
            continue
        items = R.call("GET", f"/reviewSubmissions/{sub['id']}/items",
                       include="appStoreVersion,appEvent,appCustomProductPageVersion")
        kinds = []
        for item in items["data"]:
            rel = item.get("relationships") or {}
            kind = next((k for k, v in rel.items() if (v or {}).get("data")), "item")
            kinds.append(f"{kind} ({item['attributes'].get('state')})")
        print(f"  {sub['id']}  {a.get('state')}  submitted {a.get('submittedDate') or '-'}  items: {', '.join(kinds) or 'none'}")

    print("App Store versions:")
    for v in R.call("GET", f"/apps/{app}/appStoreVersions", limit="5")["data"]:
        a = v["attributes"]
        print(f"  {a.get('versionString')}  {a.get('appStoreState') or a.get('appVersionState')}")

    print("In-App Events:")
    for e in R.call("GET", f"/apps/{app}/appEvents", limit="20")["data"]:
        a = e["attributes"]
        print(f"  {a.get('referenceName')}  {a.get('eventState')}")


if __name__ == "__main__":
    main()
