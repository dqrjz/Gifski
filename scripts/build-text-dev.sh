#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/verify-baseline.sh build

derived_data="${GIFSKI_DERIVED_DATA:-/tmp/gifski-derived-data}"
dev_directory="/tmp/gifski-text-dev"
dev_app="$dev_directory/Gifski Text Dev.app"
mkdir -p "$dev_directory"
# This is an independent disposable build, never the App Store installation.
if [ -d "$dev_app" ]; then
  rm -rf "$dev_app"
fi
ditto "$derived_data/Build/Products/Debug/Gifski.app" "$dev_app"
# Share extension/App Groups are outside local text-editor validation.
rm -rf "$dev_app/Contents/PlugIns"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.dqrjz.Gifski.TextDev' "$dev_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName Gifski Text Dev' "$dev_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Delete :CFBundleURLTypes' "$dev_app/Contents/Info.plist" 2>/dev/null || true
codesign --force --deep --sign - "$dev_app"
printf '%s\n' "$dev_app"
