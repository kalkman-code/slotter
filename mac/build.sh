#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

IDENTITY="${SNAPPY_SIGN_IDENTITY:-Apple Development: Created via API (DL3YV3TC36)}"
BUNDLE_ID="com.tobykalkman.snappy"
APP="build/Snappy.app"
INSTALL_PATH="/Applications/Snappy.app"

INSTALL=0
for arg in "$@"; do
    case "$arg" in
        --install) INSTALL=1 ;;
        *) echo "unknown argument: $arg" >&2; exit 2 ;;
    esac
done

echo "==> toolchain"
swift --version | awk 'NR==1'

echo "==> build"
swift build -c release --product Snappy
swift build -c release --product snappy-icongen
BIN="$(swift build -c release --show-bin-path)"

echo "==> assemble"
rm -rf "$APP" build/Snappy.iconset
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Snappy" "$APP/Contents/MacOS/Snappy"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> icon"
"$BIN/snappy-icongen" ../Snappy.svg build/Snappy.iconset
iconutil -c icns -o "$APP/Contents/Resources/Snappy.icns" build/Snappy.iconset

echo "==> sign"
if ! security find-identity -v -p codesigning | grep -qF "$IDENTITY"; then
    echo "signing identity not found: $IDENTITY" >&2
    echo "ad-hoc signing is deliberately not offered — it drops the Accessibility grant on every rebuild." >&2
    exit 1
fi
codesign --force --sign "$IDENTITY" \
         --identifier "$BUNDLE_ID" \
         --entitlements Snappy.entitlements \
         "$APP"
codesign --verify --strict "$APP"
codesign -dvv "$APP" 2>&1 | grep -E '^(Identifier|Authority|TeamIdentifier)' || true

if [ "$INSTALL" -eq 1 ]; then
    echo "==> install"
# Installing is not a reason to put a window on screen (Toby, 16-09-2026).
# The app comes back only if it was already open — that restores what the
# quit below takes away — and INSTALL_NO_LAUNCH suppresses even that.
WAS_RUNNING=""
if pgrep -f "${INSTALL_PATH}/Contents/MacOS/" >/dev/null 2>&1; then WAS_RUNNING=1; fi
relaunch() {
  if [ -z "$WAS_RUNNING" ] || [ -n "${INSTALL_NO_LAUNCH:-}" ]; then
    echo "Installed. Not launched - it was not running."
    return 0
  fi
  open "$@"
}

    osascript -e 'quit app "Snappy"' >/dev/null 2>&1 || pkill -x Snappy || true
    sleep 1
    rm -rf "$INSTALL_PATH"
    ditto "$APP" "$INSTALL_PATH"
    relaunch "$INSTALL_PATH"
    [ -n "$WAS_RUNNING" ] && echo "installed and launched $INSTALL_PATH" || true
else
    echo "built $PWD/$APP  (pass --install to install to /Applications)"
fi
