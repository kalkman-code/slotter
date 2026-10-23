#!/usr/bin/env bash
# Writes a local two-platform feed. SPARKLE_ED_KEY reaches Sparkle tools only over stdin.
# Usage: make-appcast.sh <final DMG> <Windows zip> <notes.html> <empty output directory> [previous appcast]
set -euo pipefail
set +x
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DMG="${1:?final stapled DMG}"
ZIP="${2:?Windows zip}"
NOTES="${3:?release notes HTML}"
OUT="${4:?empty output directory}"
PREVIOUS="${5:-}"
: "${SPARKLE_ED_KEY:?SPARKLE_ED_KEY is not set}"
absolute() { printf '%s/%s\n' "$(cd "$(dirname "$1")" && pwd)" "$(basename "$1")"; }
for file in "$DMG" "$ZIP" "$NOTES"; do [ -f "$file" ] || { echo "Missing input: $file" >&2; exit 1; }; done
DMG="$(absolute "$DMG")"; ZIP="$(absolute "$ZIP")"; NOTES="$(absolute "$NOTES")"
[ -z "$PREVIOUS" ] || PREVIOUS="$(absolute "$PREVIOUS")"
NAME="$(basename "$DMG")"; VERSION="${NAME#Slotter-}"; VERSION="${VERSION%.dmg}"
[[ "$NAME" =~ ^Slotter-[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?\.dmg$ ]] || { echo 'Expected Slotter-<version>.dmg' >&2; exit 1; }
[ "$(basename "$ZIP")" = "Slotter-$VERSION-win-x64.zip" ] || { echo 'Windows asset version must match the DMG' >&2; exit 1; }
if [ -e "$OUT" ] && [ -n "$(ls -A "$OUT")" ]; then echo 'Output directory must be empty' >&2; exit 1; fi
mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"
TOOLS="$(find "$ROOT/.build/artifacts" -path '*/Sparkle/bin' -type d | head -1)"
[ -x "$TOOLS/sign_update" ] || { echo 'Sparkle tools missing; resolve Swift packages first' >&2; exit 1; }
PUBLIC="${SLOTTER_PUBLIC_KEY:-$(plutil -extract SUPublicEDKey raw "$ROOT/Resources/Info.plist")}"
printf '%s\n' "$SPARKLE_ED_KEY" | swift "$ROOT/scripts/sparkle/key-check.swift" "$PUBLIC"
MOUNT="$OUT/.mount"; mkdir "$MOUNT"
cleanup() { hdiutil detach "$MOUNT" -quiet >/dev/null 2>&1 || true; rmdir "$MOUNT" 2>/dev/null || true; }
trap cleanup EXIT
hdiutil attach -nobrowse -readonly -noautoopen -mountpoint "$MOUNT" "$DMG" >/dev/null
PLIST="$MOUNT/Slotter.app/Contents/Info.plist"
[ "$(plutil -extract SUPublicEDKey raw "$PLIST")" = "$PUBLIC" ] || { echo 'Archive public key does not match' >&2; exit 1; }
[ "$(plutil -extract CFBundleShortVersionString raw "$PLIST")" = "$VERSION" ] || { echo 'Archive version does not match asset filename' >&2; exit 1; }
BUILD="$(plutil -extract CFBundleVersion raw "$PLIST")"
[[ "$BUILD" =~ ^[0-9]+$ ]] || { echo 'Archive build number is not numeric' >&2; exit 1; }
hdiutil detach "$MOUNT" -quiet; rmdir "$MOUNT"; trap - EXIT
cd "$OUT"
# Sparkle interprets '-' as a filename if it exists in the current directory.
[ ! -e ./- ] || { echo "Refusing a file named '-'" >&2; exit 1; }
if ! SIGNATURE="$(printf '%s\n' "$SPARKLE_ED_KEY" | "$TOOLS/sign_update" --ed-key-file - -p "$DMG" 2>/dev/null)"; then
    unset SIGNATURE; echo 'Archive signing failed; tool output withheld' >&2; exit 1
fi
[[ "$SIGNATURE" =~ ^[A-Za-z0-9+/]{86}==$ ]] || { unset SIGNATURE; echo 'Archive signing returned invalid output; withheld' >&2; exit 1; }
cp "$DMG" "$ZIP" "$OUT/"
DEFAULT_TEMPLATE='https://github.com/kalkman-code/slotter/releases/download/v{version}/'
TEMPLATE="${SLOTTER_DOWNLOAD_PREFIX:-$DEFAULT_TEMPLATE}"
swift "$ROOT/scripts/sparkle/compose-appcast.swift" "$OUT/appcast.xml" "$PREVIOUS" "$VERSION" "$BUILD" "$DMG" "$SIGNATURE" "$ZIP" "$NOTES" "$TEMPLATE"
if ! LOG="$(printf '%s\n' "$SPARKLE_ED_KEY" | "$TOOLS/sign_update" --ed-key-file - -p "$OUT/appcast.xml" 2>&1)"; then
    unset LOG; echo 'Feed signing failed; tool output withheld' >&2; exit 1
fi
unset LOG SIGNATURE
swift "$ROOT/scripts/sparkle/verify-appcast.swift" "$OUT/appcast.xml" "$PUBLIC" "$OUT" "$TEMPLATE"
echo "Appcast for $VERSION (build $BUILD): $OUT/appcast.xml"
