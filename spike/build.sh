#!/usr/bin/env bash
# Builds the spike tools into spike/build/ (gitignored). The server becomes an ad-hoc signed
# PhoneBoxSpike.app so that macOS attributes network permissions to it, not to Terminal.
set -euo pipefail

SPIKE="$(cd "$(dirname "$0")" && pwd)"
OUT="$SPIKE/build"
APP="$OUT/PhoneBoxSpike.app"
mkdir -p "$OUT"

for tool in usbwatch sensors commands make-video; do
  swiftc -O "$SPIKE/$tool.swift" -o "$OUT/$tool"
done

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/web"
swiftc -O "$SPIKE/server/main.swift" -o "$APP/Contents/MacOS/PhoneBoxSpike"
cp "$SPIKE/server/Info.plist" "$APP/Contents/Info.plist"
cp "$SPIKE/web/index.html" "$APP/Contents/Resources/web/"
"$OUT/make-video" "$APP/Contents/Resources/web"
xattr -cr "$APP"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
echo "Built $OUT"
