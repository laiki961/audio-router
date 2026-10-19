#!/bin/zsh
# Builds build/AudioRouter.app (requires Xcode Command Line Tools: xcode-select --install)
set -euo pipefail
cd "$(dirname "$0")"

APP=build/AudioRouter.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O -parse-as-library \
  -target "$(uname -m)-apple-macos14.4" \
  Sources/*.swift \
  -o "$APP/Contents/MacOS/AudioRouter"

cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Built $APP"
