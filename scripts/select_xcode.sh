#!/usr/bin/env bash
# Selects the newest installed Xcode 26 or later. App Store Connect requires
# builds made with the iOS 26 SDK; CI tests use the same compiler.
set -euo pipefail
candidate=$(ls -d /Applications/Xcode_*.app 2>/dev/null \
  | sed -E 's#.*/Xcode_([0-9.]+)\.app#\1 &#' \
  | awk '$1+0 >= 26' \
  | sort -V | tail -1 | cut -d' ' -f2- || true)
if [ -z "$candidate" ]; then
  echo "::error::No Xcode 26 or later on this runner. Installed:"; ls -d /Applications/Xcode*.app
  exit 1
fi
sudo xcode-select -s "$candidate/Contents/Developer"
xcodebuild -version
