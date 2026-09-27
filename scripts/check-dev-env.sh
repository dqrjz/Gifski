#!/bin/bash
set -u
export PATH="$HOME/.cargo/bin:/opt/homebrew/bin:$PATH"
missing=0
echo 'Developer tools'
for tool in git gh rustup rustc cargo swiftlint; do
  if command -v "$tool" >/dev/null 2>&1; then
    if [ "$tool" = swiftlint ]; then "$tool" version; else "$tool" --version; fi
  else
    echo "MISSING: $tool"
    missing=1
  fi
done
echo 'Xcode'
if ! xcodebuild -version; then
  echo 'Install full Xcode, finish first-launch setup, and select its Developer directory.'
  missing=1
fi
echo 'Metal compiler'
if ! xcrun metal --version; then
  echo 'Run: xcodebuild -downloadComponent MetalToolchain'
  missing=1
fi
echo 'GitHub CLI authentication (needed for CLI push/PR workflow)'
if ! gh auth status; then
  echo 'Run: gh auth login --hostname github.com --git-protocol https --web'
  missing=1
fi
exit "$missing"
