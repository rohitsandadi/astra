#!/bin/bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASTRA_VERSION="${ASTRA_VERSION:-0.1.0}"
STAGE="$REPO_ROOT/build/dmg-stage"
DIST="$REPO_ROOT/dist"
DMG_NAME="Astra-$ASTRA_VERSION.dmg"
DMG="$DIST/$DMG_NAME"

if [[ "${ASTRA_SKIP_BUILD:-0}" != "1" ]]; then
  "$REPO_ROOT/scripts/build-app.sh"
fi

rm -rf "$STAGE"
mkdir -p "$STAGE" "$DIST"
cp -R "$REPO_ROOT/build/Astra.app" "$STAGE/Astra.app"
cp "$REPO_ROOT/LICENSE" "$STAGE/LICENSE.txt"
cp "$REPO_ROOT/README.md" "$STAGE/README.md"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG" "$DMG.sha256"
hdiutil create -volname "Astra" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
(
  cd "$DIST"
  shasum -a 256 "$DMG_NAME" > "$DMG_NAME.sha256"
)
echo "Packaged $DMG"
