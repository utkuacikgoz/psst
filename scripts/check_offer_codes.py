"""Read-only: counts the in-app purchases' offer codes (custom codes such as the one in
the store-check input, and one-time code batches) with how many are active and when they
expire, and, given CODE, says whether that code exists (with its active/expiry/redemption
limit), so a new code can be checked without redeeming it. The Actions log is public, so
no code is ever printed, only counts. Never changes anything; prints no keys.
Reads ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8, BUNDLE_ID and optional CODE.
"""
import os

import release as R


def get(path, **query):
    try:
        return R.call("GET", path, **query)
    except SystemExit as refused:
        print(f"  ({path}: {refused})")
        return {"data": [], "included": []}


def summary(codes):
    """Counts only: how many, how many active, and the expiry dates (never a code)."""
    active = sum(1 for c in codes if c["attributes"].get("active"))
    expiries = sorted({str(c["attributes"].get("expirationDate")) for c in codes})
    return f"{len(codes)} ({active} active; expires {', '.join(expiries) if codes else '-'})"


def main():
    want = (os.environ.get("CODE") or "").strip().upper()
    app = R.call("GET", "/apps", **{"filter[bundleId]": os.environ["BUNDLE_ID"]})["data"][0]["id"]
    iaps = get(f"/apps/{app}/inAppPurchasesV2", limit="50")["data"]
    found = []
    for iap in iaps:
        a = iap["attributes"]
        print(f"In-app purchase {a.get('productId')} ({a.get('inAppPurchaseType')}, {a.get('state')})")
        offers = get(f"/v2/inAppPurchases/{iap['id']}/offerCodes", limit="50")
        for number, offer in enumerate(offers["data"], 1):
            o = offer["attributes"]
            custom = get(f"/v1/inAppPurchaseOfferCodes/{offer['id']}/customCodes", limit="200")["data"]
            batches = get(f"/v1/inAppPurchaseOfferCodes/{offer['id']}/oneTimeUseCodes", limit="200")["data"]
            names = {str(c["attributes"].get("customCode", "")).upper() for c in custom}
            # An offer's reference name can be the code itself: don't print it then.
            name = o.get("name")
            label = f"'{name}'" if name and str(name).upper() not in names else f"#{number}"
            one_time = sum(int(b["attributes"].get("numberOfCodes") or 0) for b in batches)
            print(f"  offer {label}: active={o.get('active')} mode={o.get('offerMode')} "
                  f"duration={o.get('duration')} periods={o.get('numberOfPeriods')}")
            print(f"    custom codes: {summary(custom)}")
            print(f"    one-time code batches: {summary(batches)}, {one_time} codes in all")
            for c in custom:
                attributes = c["attributes"]
                if want and str(attributes.get("customCode", "")).strip().upper() == want:
                    found.append((a.get("productId"), label, attributes))
    if want:
        if not found:
            print("The code: NOT found on any in-app purchase.")
        for product, label, c in found:
            print(f"The code: found on {product}, offer {label}: active={c.get('active')} "
                  f"expires={c.get('expirationDate')} redemption limit={c.get('numberOfCodes')}")


if __name__ == "__main__":
    main()
