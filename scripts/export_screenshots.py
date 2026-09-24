#!/usr/bin/env python3
"""Export screenshot attachments from an .xcresult bundle with readable file names."""
import json
import pathlib
import re
import shutil
import subprocess
import sys

result, out = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
raw = out / "raw"
raw.mkdir(parents=True, exist_ok=True)
subprocess.check_call(["xcrun", "xcresulttool", "export", "attachments",
                       "--path", str(result), "--output-path", str(raw)])
manifest = json.loads((raw / "manifest.json").read_text())
count = 0
for test in manifest:
    for item in test.get("attachments", []):
        name = item.get("suggestedHumanReadableName") or item["exportedFileName"]
        # Only our named screenshots ("device · size · step"); XCTest adds its own
        # attachments (logs, failure captures) that aren't part of the review set.
        if " · " not in name or not item["exportedFileName"].lower().endswith((".png", ".jpg", ".jpeg")):
            continue
        name = re.sub(r"_\d+_[0-9A-F-]{36}", "", name)  # drop xcresult suffix
        name = re.sub(r"[^\w.·() -]+", "_", name).replace(" · ", "__")
        if not name.endswith(".png"):
            name += ".png"
        shutil.copy(raw / item["exportedFileName"], out / name)
        count += 1
shutil.rmtree(raw)
print(f"exported {count} screenshots to {out}")
