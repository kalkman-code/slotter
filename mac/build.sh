#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

IDENTITY="${SLOTTER_SIGN_IDENTITY:-Apple Development: Created via API (DL3YV3TC36)}"
BUNDLE_ID="uk.co.kalkman.slotter"
APP="build/Slotter.app"
INSTALL_PATH="/Applications/Slotter.app"
OLD_APP="/Applications/Snappy.app"
VERSION="$(tr -d '[:space:]' < ../VERSION)"
SHORT_VERSION="${VERSION%%-*}"
BUILD_NUMBER="$(git -C .. rev-list --count HEAD)"

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
swift build -c release --product Slotter
swift build -c release --product slotter-icongen
BIN="$(swift build -c release --show-bin-path)"

echo "==> assemble"
rm -rf "$APP" build/Slotter.iconset
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Slotter" "$APP/Contents/MacOS/Slotter"
cp Resources/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $SHORT_VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> fonts"
mkdir -p "$APP/Contents/Resources/Fonts"
cp ../fonts/*.ttf ../fonts/OFL.txt "$APP/Contents/Resources/Fonts/"

echo "==> icon"
"$BIN/slotter-icongen" ../Slotter.svg build/Slotter.iconset
iconutil -c icns -o "$APP/Contents/Resources/Slotter.icns" build/Slotter.iconset

echo "==> sign"
if ! security find-identity -v -p codesigning | grep -qF "$IDENTITY"; then
    echo "signing identity not found: $IDENTITY" >&2
    echo "ad-hoc signing is deliberately not offered — it drops the Accessibility grant on every rebuild." >&2
    exit 1
fi
codesign --force --sign "$IDENTITY" \
         --identifier "$BUNDLE_ID" \
         --entitlements Slotter.entitlements \
         "$APP"
codesign --verify --strict "$APP"
codesign -dvv "$APP" 2>&1 | grep -E '^(Identifier|Authority|TeamIdentifier)' || true

if [ "$INSTALL" -eq 1 ]; then
    echo "==> install"
    # Installing is not a reason to put a window on screen. The app comes back only if it
    # (or Snappy, its name before 1.0) was already open, and INSTALL_NO_LAUNCH suppresses even that.
    WAS_RUNNING=""
    if pgrep -f "${INSTALL_PATH}/Contents/MacOS/" >/dev/null 2>&1 || pgrep -x Snappy >/dev/null 2>&1; then WAS_RUNNING=1; fi

    osascript -e 'quit app "Slotter"' >/dev/null 2>&1 || pkill -x Slotter || true
    sleep 1
    rm -rf "$INSTALL_PATH"
    ditto "$APP" "$INSTALL_PATH"
    # Nothing built stays in the repo: Spotlight would list the staged copy beside the real one.
    rm -rf build

    # Retire Snappy only once Slotter is on disk.
    if [ -d "$OLD_APP" ]; then
        osascript -e 'quit app "Snappy"' >/dev/null 2>&1 || pkill -x Snappy || true
        sleep 1
        rm -rf "$OLD_APP"
        echo "removed $OLD_APP"
    fi

    if [ -n "$WAS_RUNNING" ] && [ -z "${INSTALL_NO_LAUNCH:-}" ]; then
        open "$INSTALL_PATH"
        echo "installed and launched $INSTALL_PATH"
    else
        echo "installed $INSTALL_PATH - not launched, it was not running"
    fi
else
    echo "built $PWD/$APP  (pass --install to install to /Applications)"
fi
