#!/usr/bin/env bash
# This explicitly authorised proof temporarily installs staging bundles, exercises Sparkle, then restores.
# SPARKLE_CLI=<matching 2.10.0 sparkle.app/Contents/MacOS/sparkle> stage-update-test.sh <empty work dir>
set -euo pipefail
set +x
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
W="${1:?empty work directory}"
CLI="${SPARKLE_CLI:?path to Sparkle 2.10.0 sparkle-cli executable}"
IDENTITY="${SLOTTER_SIGN_IDENTITY:-Developer ID Application: Toby Kalkman (YNL35YT683)}"
APP=/Applications/Slotter.app
KEY_ACCOUNT="slotter-staging-$(uuidgen)"
[ -d "$ROOT/build/Slotter.app" ] || { echo 'Build the normal current app first with mac/build.sh' >&2; exit 1; }
[ ! -e "$W" ] || [ -z "$(ls -A "$W")" ] || { echo 'Work directory must be empty' >&2; exit 1; }
mkdir -p "$W"; W="$(cd "$W" && pwd)"
WAS_RUNNING=0
pgrep -x Slotter >/dev/null && WAS_RUNNING=1
ditto "$ROOT/build/Slotter.app" "$W/normal/Slotter.app"
HAD_DEFAULTS=0
if defaults export uk.co.kalkman.slotter "$W/defaults.plist" >/dev/null 2>&1; then HAD_DEFAULTS=1; fi
SERVER=""; KEY_CREATED=0; REPLACED=0
cleanup() {
    local status=$?
    if [ -n "$SERVER" ]; then kill "$SERVER" 2>/dev/null || true; wait "$SERVER" 2>/dev/null || true; fi
    if [ "$REPLACED" -eq 1 ]; then
        pkill -x Slotter 2>/dev/null || true
        sleep 1
        rm -rf "${APP:?}"
        ditto "$W/normal/Slotter.app" "$APP"
        if [ "$HAD_DEFAULTS" -eq 1 ]; then defaults import uk.co.kalkman.slotter "$W/defaults.plist" >/dev/null; else defaults delete uk.co.kalkman.slotter >/dev/null 2>&1 || true; fi
        codesign --verify --deep --strict "$APP"
        if [ "$WAS_RUNNING" -eq 1 ]; then open -g "$APP"; fi
        echo "restored normal version=$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist") real_key=$(plutil -extract SUPublicEDKey raw "$APP/Contents/Info.plist") previous_running=$WAS_RUNNING"
    fi
    if [ "$KEY_CREATED" -eq 1 ]; then swift "$ROOT/scripts/sparkle/staging-key.swift" delete "$KEY_ACCOUNT"; fi
    return "$status"
}
trap cleanup EXIT
PUBLIC="$(swift "$ROOT/scripts/sparkle/staging-key.swift" create "$KEY_ACCOUNT")"
KEY_CREATED=1
PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
BASE="http://127.0.0.1:$PORT"
BUILD="$(plutil -extract CFBundleVersion raw "$W/normal/Slotter.app/Contents/Info.plist")"
OLD_BUILD=$((BUILD + 1000)); NEW_BUILD=$((BUILD + 1001))
stage() {
    local version="$1" build="$2" target="$3"
    ditto "$W/normal/Slotter.app" "$target/Slotter.app"
    local plist="$target/Slotter.app/Contents/Info.plist"
    plutil -replace CFBundleShortVersionString -string "$version" "$plist"
    plutil -replace CFBundleVersion -string "$build" "$plist"
    plutil -replace SUPublicEDKey -string "$PUBLIC" "$plist"
    plutil -replace SUFeedURL -string "$BASE/feed/appcast.xml" "$plist"
    codesign --force --sign "$IDENTITY" --options runtime --timestamp --entitlements "$ROOT/Slotter-release.entitlements" "$target/Slotter.app"
    codesign --verify --deep --strict "$target/Slotter.app"
}
stage 1.0.0-alpha.2 "$OLD_BUILD" "$W/old"
stage 1.0.0-alpha.99 "$NEW_BUILD" "$W/new"
mkdir -p "$W/dmg-root" "$W/archives" "$W/www/feed" "$W/www/v1.0.0-alpha.99"
ditto "$W/new/Slotter.app" "$W/dmg-root/Slotter.app"
ln -s /Applications "$W/dmg-root/Applications"
hdiutil create -volname Slotter -srcfolder "$W/dmg-root" -format UDZO -ov "$W/archives/Slotter-1.0.0-alpha.99.dmg" >/dev/null
printf 'Synthetic Windows asset for macOS feed-selection proof\n' > "$W/Slotter.exe"
zip -q -j "$W/archives/Slotter-1.0.0-alpha.99-win-x64.zip" "$W/Slotter.exe"
printf '<h2>Local staged update</h2><p>Disposable alpha.99 proof.</p>\n' > "$W/notes.html"
SLOTTER_PUBLIC_KEY="$PUBLIC" SLOTTER_DOWNLOAD_PREFIX="$BASE/v{version}/" \
    swift "$ROOT/scripts/sparkle/staging-key.swift" run "$KEY_ACCOUNT" /bin/bash "$ROOT/scripts/make-appcast.sh" \
    "$W/archives/Slotter-1.0.0-alpha.99.dmg" "$W/archives/Slotter-1.0.0-alpha.99-win-x64.zip" "$W/notes.html" "$W/generated" > "$W/appcast.log" 2>&1
cp "$W/generated/appcast.xml" "$W/www/feed/"
cp "$W/archives/"* "$W/www/v1.0.0-alpha.99/"
(cd "$W/www" && exec python3 -m http.server "$PORT" --bind 127.0.0.1 > "$W/http.log" 2>&1) &
SERVER=$!
for _ in $(seq 50); do curl -fsS "$BASE/feed/appcast.xml" >/dev/null 2>&1 && break; sleep 0.2; done
REPLACED=1
pkill -x Slotter 2>/dev/null || true
sleep 1
rm -rf "${APP:?}"
ditto "$W/old/Slotter.app" "$APP"
defaults write uk.co.kalkman.slotter SUEnableAutomaticChecks -bool false
open -g "$APP"
sleep 3
pgrep -x Slotter >/dev/null
echo "installed running alpha.2 build=$OLD_BUILD; staged alpha.99 build=$NEW_BUILD"
"$CLI" "$APP" --probe --user-agent-name 'Slotter staging test' --verbose > "$W/probe.log" 2>&1
echo 'Sparkle probe: newer update found'
LOG="$HOME/Library/Logs/Slotter/slotter.log"
LINES="$(wc -l < "$LOG")"
"$CLI" "$APP" --check-immediately --user-agent-name 'Slotter staging test' --verbose > "$W/install.log" 2>&1
for _ in $(seq 50); do
    if tail -n +"$((LINES + 1))" "$LOG" | grep -q "version=1.0.0-alpha.99, build=$NEW_BUILD"; then break; fi
    sleep 0.2
done
[ "$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")" = 1.0.0-alpha.99 ]
[ "$(plutil -extract CFBundleVersion raw "$APP/Contents/Info.plist")" = "$NEW_BUILD" ]
tail -n +"$((LINES + 1))" "$LOG" | grep "version=1.0.0-alpha.99, build=$NEW_BUILD"
pgrep -fl "$APP/Contents/MacOS/Slotter"
codesign --verify --deep --strict "$APP"
echo 'Sparkle update: signed archive verified, installed, relaunched and reported alpha.99'
