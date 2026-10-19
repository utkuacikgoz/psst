"""Read-only: lists the in-app purchases and their offer codes (custom codes such as
BUILDHOP50), with whether each is active, its price/discount and remaining redemptions,
so a new code can be checked without redeeming it. Never changes anything; prints no keys.
Reads ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8, BUNDLE_ID and optional CODE.
"""
import json
import os

import release as R


def get(path, **query):
    try:
        return R.call("GET", path, **query)
    except SystemExit as refused:
        print(f"  ({path}: {refused})")
        return {"data": [], "included": []}


def main():
    want = (os.environ.get("CODE") or "").strip().upper()
    app = R.call("GET", "/apps", **{"filter[bundleId]": os.environ["BUNDLE_ID"]})["data"][0]["id"]
    iaps = get(f"/apps/{app}/inAppPurchasesV2", limit="50")["data"]
    found = False
    for iap in iaps:
        a = iap["attributes"]
        print(f"In-app purchase {a.get('productId')} ({a.get('inAppPurchaseType')}, {a.get('state')})")
        offers = get(f"/v2/inAppPurchases/{iap['id']}/offerCodes", limit="50")
        for offer in offers["data"]:
            o = offer["attributes"]
            print(f"  offer '{o.get('name')}': active={o.get('active')} " +
                  json.dumps({k: v for k, v in o.items() if k not in ('name', 'active')}, default=str)[:300])
            for rel in ("customCodes", "oneTimeUseCodes"):
                codes = get(f"/v1/inAppPurchaseOfferCodes/{offer['id']}/{rel}", limit="200")["data"]
                for code in codes:
                    c = code["attributes"]
                    label = c.get("customCode") or f"{c.get('numberOfCodes')} one-time codes"
                    match = bool(want) and str(c.get("customCode", "")).upper() == want
                    found |= match
                    print(f"    {rel[:-1]}: {label} active={c.get('active')} "
                          f"redemptions={c.get('numberOfCodes')} expires={c.get('expirationDate')}{'  <== ' + want if match else ''}")
    if want:
        print(f"{want}: {'found' if found else 'NOT found on any in-app purchase'}.")


if __name__ == "__main__":
    main()
