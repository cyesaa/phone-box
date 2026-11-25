#!/usr/bin/env bash
# Builds build/PhoneBox.app (release): binary, Info.plist, translations, dashboard files, the keep-awake video and
# mediaremote-adapter (script + framework). Ad-hoc signed, like NotchBox.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/PhoneBox.app"

"$ROOT/scripts/build-adapter.sh"
swift build --package-path "$ROOT" -c release
BIN_DIR="$(swift build --package-path "$ROOT" -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

cp "$BIN_DIR/PhoneBox" "$APP/Contents/MacOS/PhoneBox"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
# Translations go straight into Contents/Resources so that Bundle.main finds them.
ditto "$ROOT/Resources/en.lproj" "$APP/Contents/Resources/en.lproj"
ditto "$ROOT/Resources/tr.lproj" "$APP/Contents/Resources/tr.lproj"
ditto "$ROOT/Resources/web" "$APP/Contents/Resources/web"
cp "$ROOT/Vendor/mediaremote-adapter/bin/mediaremote-adapter.pl" "$APP/Contents/Resources/mediaremote-adapter.pl"
ditto "$ROOT/build/adapter/MediaRemoteAdapter.framework" "$APP/Contents/Frameworks/MediaRemoteAdapter.framework"
swiftc -O -suppress-warnings "$ROOT/scripts/make-video.swift" -o "$ROOT/build/make-video"
"$ROOT/build/make-video" "$APP/Contents/Resources/web/keepawake.mp4"

xattr -cr "$APP"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
echo "Built $APP"
