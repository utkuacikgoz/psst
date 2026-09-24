#!/usr/bin/env python3
"""Print simulator UDIDs from the newest iOS runtime: `any`, `compact`, or `large`."""
import json
import subprocess
import sys

kind = sys.argv[1] if len(sys.argv) > 1 else "any"
listing = json.loads(subprocess.check_output(
    ["xcrun", "simctl", "list", "devices", "available", "-j"]))["devices"]

def runtime_key(name):
    version = name.rsplit("iOS-", 1)[-1]
    return tuple(int(p) for p in version.split("-") if p.isdigit())

runtimes = sorted((r for r in listing if "iOS" in r), key=runtime_key, reverse=True)
phones = [d for r in runtimes for d in listing[r] if d["name"].startswith("iPhone")]
if not phones:
    sys.exit("no iPhone simulators available")

def first(preferences):
    for pref in preferences:
        for d in phones:
            if pref in d["name"]:
                return d
    return phones[0]

if kind == "compact":
    device = first(["iPhone SE", "mini", "iPhone 16e", "iPhone 17e"])
elif kind == "large":
    device = first(["Pro Max", "Plus", "Air"])
else:
    device = phones[0]
print(device["udid"])
print(device["name"], file=sys.stderr)
