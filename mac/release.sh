#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION="${SLOTTER_VERSION:-$(tr -d '[:space:]' < "$PROJECT_DIR/VERSION")}"
BUILD_NUMBER="${SLOTTER_BUILD:-$(git -C "$PROJECT_DIR" rev-list --count HEAD)}"
IDENTITY="Developer ID Application: Toby Kalkman (YNL35YT683)"
KEY_DIR="$HOME/.appstoreconnect"
APP="$PROJECT_DIR/dist/Slotter.app"
DMG="$PROJECT_DIR/dist/Slotter-$VERSION.dmg"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/slotter-release.XXXXXX")"
LEAK_SCANNER="$HOME/hub/Scripts/release-leak-scan.py"
BUILD_FLAGS=(
    -Xswiftc -file-prefix-map -Xswiftc "$PROJECT_DIR=."
    -Xswiftc -debug-prefix-map -Xswiftc "$SCRIPT_DIR/.build=."
    -Xcc "-fdebug-prefix-map=$SCRIPT_DIR/.build=."
    -Xcc "-ffile-prefix-map=$SCRIPT_DIR/.build=."
)
cleanup() { rm -rf "${STAGING_DIR:?}"; }
trap cleanup EXIT

case "$(swift --version | head -n 1)" in
    *beta*|*Beta*|*snapshot*|*Snapshot*|*development*|*Development*|*rc*)
        echo "Refusing a release build with a pre-release Swift toolchain" >&2
        exit 1
        ;;
esac
swift --version | head -n 1

if [ -n "$(git -C "$PROJECT_DIR" status --porcelain -- . ':(exclude)docs/release-notes-*.md' ':(exclude)todo.md')" ]; then
    echo "uncommitted source changes outside release notes and todo.md; commit them before packaging" >&2
    exit 1
fi

KEY_ID="$(cat "$KEY_DIR/key_id")"
KEY_PATH="$KEY_DIR/private_keys/AuthKey_$KEY_ID.p8"
[ -f "$KEY_PATH" ] && [ -s "$KEY_DIR/issuer_id" ] \
    || { echo "the pinned App Store Connect key is missing from $KEY_DIR" >&2; exit 1; }
security find-identity -v -p codesigning | grep -Fq "$IDENTITY" \
    || { echo "signing identity not found: $IDENTITY" >&2; exit 1; }

cd "$SCRIPT_DIR"
swift build -c release --disable-sandbox "${BUILD_FLAGS[@]}" --product Slotter
swift build -c release --disable-sandbox "${BUILD_FLAGS[@]}" --product slotter-icongen
BIN="$(swift build -c release --disable-sandbox "${BUILD_FLAGS[@]}" --show-bin-path)"

mkdir -p "$PROJECT_DIR/dist"
rm -rf "${APP:?}" "${STAGING_DIR:?}/Slotter.iconset" "$STAGING_DIR/Slotter.dmg-root"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Fonts" "$STAGING_DIR/Slotter.dmg-root"
cp "$BIN/Slotter" "$APP/Contents/MacOS/Slotter"
strip -x -S "$APP/Contents/MacOS/Slotter"
cp "$SCRIPT_DIR/Resources/Info.plist" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
[ -z "${SLOTTER_PUBLIC_KEY:-}" ] || plutil -replace SUPublicEDKey -string "$SLOTTER_PUBLIC_KEY" "$APP/Contents/Info.plist"
[ -z "${SLOTTER_FEED_URL:-}" ] || plutil -replace SUFeedURL -string "$SLOTTER_FEED_URL" "$APP/Contents/Info.plist"
cp ../fonts/*.ttf ../fonts/OFL.txt "$APP/Contents/Resources/Fonts/"
cp "$PROJECT_DIR/LICENSE" "$APP/Contents/Resources/LICENSE"
printf 'APPL????' > "$APP/Contents/PkgInfo"
"$BIN/slotter-icongen" ../Slotter.svg "$STAGING_DIR/Slotter.iconset"
iconutil -c icns -o "$APP/Contents/Resources/Slotter.icns" "$STAGING_DIR/Slotter.iconset"

bash "$SCRIPT_DIR/scripts/package-sparkle.sh" "$APP" "$IDENTITY" "$SCRIPT_DIR/Slotter-release.entitlements"
python3 "$LEAK_SCANNER" "$APP"
codesign --verify --deep --strict "$APP"
ditto -c -k --keepParent "$APP" "$STAGING_DIR/Slotter.zip"
xcrun notarytool submit "$STAGING_DIR/Slotter.zip" \
    --key "$KEY_PATH" --key-id "$KEY_ID" --issuer "$(cat "$KEY_DIR/issuer_id")" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

ditto "$APP" "$STAGING_DIR/Slotter.dmg-root/Slotter.app"
ln -s /Applications "$STAGING_DIR/Slotter.dmg-root/Applications"
hdiutil create -volname Slotter -srcfolder "$STAGING_DIR/Slotter.dmg-root" \
    -ov -format UDZO "$DMG"
python3 "$LEAK_SCANNER" "$DMG"
codesign --force --sign "$IDENTITY" --timestamp "$DMG"
xcrun notarytool submit "$DMG" \
    --key "$KEY_PATH" --key-id "$KEY_ID" --issuer "$(cat "$KEY_DIR/issuer_id")" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
python3 "$LEAK_SCANNER" "$DMG"
spctl --assess --type execute --verbose=2 "$APP"
codesign --verify --deep --strict "$APP"
SPCTL_OUTPUT="$(spctl -a -vv -t open --context context:primary-signature "$DMG" 2>&1)" || {
    printf '%s\n' "$SPCTL_OUTPUT" >&2
    exit 1
}
printf '%s\n' "$SPCTL_OUTPUT"
case "$SPCTL_OUTPUT" in
    *": accepted"*) ;;
    *) echo "DMG primary-signature assessment did not say accepted" >&2; exit 1 ;;
esac
shasum -a 256 "$DMG" > "$DMG.sha256"
printf 'Created %s\n' "$DMG"
cat "$DMG.sha256"
