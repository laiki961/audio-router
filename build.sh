#!/bin/zsh
# Builds build/AudioRouter.app (Apple Silicon + Intel) and build/AudioRouter.zip.
# Requires Xcode Command Line Tools: xcode-select --install
# Usage: ./build.sh            build only
#        ./build.sh install    build, then copy to /Applications
set -euo pipefail
cd "$(dirname "$0")"

APP=build/AudioRouter.app
BIN="$APP/Contents/MacOS/AudioRouter"
rm -rf "$APP" build/AudioRouter.zip build/arch
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/arch

for arch in arm64 x86_64; do
  swiftc -O -parse-as-library \
    -target "$arch-apple-macos14.4" \
    Sources/*.swift \
    -o "build/arch/AudioRouter-$arch"
done
lipo -create build/arch/AudioRouter-* -output "$BIN"

cp Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign - "$APP"
ditto -c -k --keepParent "$APP" build/AudioRouter.zip
echo "Built $APP and build/AudioRouter.zip"

if [[ "${1:-}" == "install" ]]; then
  rm -rf /Applications/AudioRouter.app
  ditto "$APP" /Applications/AudioRouter.app
  echo "Installed /Applications/AudioRouter.app"
fi
