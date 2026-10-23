#!/usr/bin/env bash
# Shared by development and release packaging; preserve Downloader's sandbox entitlements.
set -euo pipefail

APP="${1:?app bundle}"
IDENTITY="${2:?signing identity}"
ENTITLEMENTS="${3:?app entitlements}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPARKLE="$(find "$ROOT/.build/artifacts" -path '*/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework' -type d | head -1)"
[ -d "$SPARKLE" ] || { echo 'Sparkle.framework missing; resolve Swift packages first' >&2; exit 1; }
mkdir -p "$APP/Contents/Frameworks"
ditto "$SPARKLE" "$APP/Contents/Frameworks/Sparkle.framework"
install -m 644 "$(dirname "$(dirname "$(dirname "$SPARKLE")")")/LICENSE" "$APP/Contents/Resources/Sparkle-LICENSE.txt"
if ! otool -l "$APP/Contents/MacOS/Slotter" | grep -q '@executable_path/../Frameworks'; then
    install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/Slotter"
fi
# Universal/debug-map object paths otherwise survive release optimisation and prefix maps.
strip -S -x "$APP/Contents/MacOS/Slotter"
FW="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
SIGN=(codesign --force --sign "$IDENTITY" --options runtime --timestamp)
"${SIGN[@]}" "$FW/XPCServices/Installer.xpc"
"${SIGN[@]}" --preserve-metadata=entitlements "$FW/XPCServices/Downloader.xpc"
"${SIGN[@]}" "$FW/Autoupdate"
"${SIGN[@]}" "$FW/Updater.app"
"${SIGN[@]}" "$APP/Contents/Frameworks/Sparkle.framework"
"${SIGN[@]}" --identifier uk.co.kalkman.slotter --entitlements "$ENTITLEMENTS" "$APP"
codesign --verify --deep --strict "$APP"
