#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$PROJECT_DIR/VERSION")"
DEST="${1:-}"
SCANNER="$HOME/hub/Scripts/release-leak-scan.py"

if [ -z "$DEST" ] || [ "$#" -ne 1 ]; then
    echo "usage: $0 <dest-clone>" >&2
    exit 2
fi
if [ ! -d "$DEST/.git" ] && [ ! -f "$DEST/.git" ]; then
    echo "destination must be an existing git clone: $DEST" >&2
    exit 2
fi
DEST="$(cd "$DEST" && pwd)"
[ "$DEST" != "$PROJECT_DIR" ] || { echo "destination must be a separate clone" >&2; exit 2; }
ORIGIN="$(git -C "$DEST" remote get-url origin)"
case "$ORIGIN" in
    *github.com:kalkman-code/slotter.git|*github.com/kalkman-code/slotter.git) ;;
    *) echo "destination origin is not kalkman-code/slotter on GitHub" >&2; exit 2 ;;
esac
[ -f "$SCANNER" ] || { echo "leak scanner not found: $SCANNER" >&2; exit 1; }
[ -f "$PROJECT_DIR/docs/release-notes-$VERSION.md" ] \
    || { echo "release notes missing for $VERSION" >&2; exit 1; }
[ -z "$(git -C "$PROJECT_DIR" status --porcelain)" ] \
    || { echo "source tree has uncommitted changes; commit the prepared release first" >&2; exit 1; }
[ -z "$(git -C "$DEST" status --porcelain)" ] \
    || { echo "destination clone has uncommitted changes" >&2; exit 1; }

STAGING="$(mktemp -d "${TMPDIR:-/tmp}/slotter-public.XXXXXX")"
trap 'rm -rf "${STAGING:?}"' EXIT
EXPORT="$STAGING/export"
mkdir -p "$EXPORT"
git -C "$PROJECT_DIR" archive --format=tar HEAD | tar -xf - -C "$EXPORT"
rm -rf "${EXPORT:?}/todo.md" "$EXPORT/docs" "$EXPORT/PRODUCT.md" \
    "$EXPORT/graphify-out" "$EXPORT/artifacts"
cp "$PROJECT_DIR/docs/release-notes-$VERSION.md" "$EXPORT/RELEASE-NOTES.md"

python3 "$SCANNER" "$EXPORT"

git -C "$DEST" rm -r -f -- .
git -C "$DEST" clean -fdx
cp -R "$EXPORT/." "$DEST/"
git -C "$DEST" add -A
echo "Export staged in $DEST; inspect the index before committing. Nothing was pushed."
