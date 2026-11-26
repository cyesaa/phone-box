#!/usr/bin/env bash
# Builds build/PhoneBox.app (release): binary, Info.plist, the app icon, translations, dashboard files, the keep-awake
# video, the Home Screen icon, mediaremote-adapter (script + framework), the licence and the third-party notices.
# Ad-hoc signed, like NotchBox.
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
swiftc -O -suppress-warnings "$ROOT/scripts/make-touch-icon.swift" -o "$ROOT/build/make-touch-icon"
"$ROOT/build/make-touch-icon" "$APP/Contents/Resources/web/apple-touch-icon.png"
swiftc -O -suppress-warnings "$ROOT/scripts/make-icon.swift" -o "$ROOT/build/make-icon"
"$ROOT/build/make-icon" "$ROOT/build/AppIcon.iconset"
iconutil -c icns "$ROOT/build/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT/LICENSE" "$ROOT/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/"

xattr -cr "$APP"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
echo "Built $APP"
