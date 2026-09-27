#!/bin/bash
set -euo pipefail
export PATH="$HOME/.cargo/bin:/opt/homebrew/bin:$PATH"
cd "$(dirname "$0")/.."

action="${1:-test}"
case "$action" in
  build|test) ;;
  *) echo "Usage: bash scripts/verify-baseline.sh [build|test]" >&2; exit 2 ;;
esac

derived_data="${GIFSKI_DERIVED_DATA:-/tmp/gifski-derived-data}"
if [ "$action" = build ]; then
  xcodebuild -project Gifski.xcodeproj -scheme Gifski -configuration Debug \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath "$derived_data" \
    CODE_SIGNING_ALLOWED=NO build
else
  # Local tests only: omit upstream App Group entitlements and use ad-hoc signing.
  # This does not validate sharing extensions or production signing.
  xcodebuild -project Gifski.xcodeproj -scheme Gifski -configuration Debug \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath "$derived_data" \
    CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
    CODE_SIGN_ENTITLEMENTS= test
fi
