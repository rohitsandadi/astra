#!/bin/bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
ASTRA_VERSION="${ASTRA_VERSION:-0.1.0}"
ASTRA_BUILD_NUMBER="${ASTRA_BUILD_NUMBER:-1}"
ASTRA_ARCHS="${ASTRA_ARCHS:-arm64 x86_64}"
APP_ROOT="$REPO_ROOT/build/Astra.app"
CONTENTS="$APP_ROOT/Contents"

ARCH_FLAGS=()
for architecture in $ASTRA_ARCHS; do
  case "$architecture" in
    arm64|x86_64) ARCH_FLAGS+=(--arch "$architecture") ;;
    *) echo "Unsupported ASTRA_ARCHS entry: $architecture" >&2; exit 2 ;;
  esac
done

export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-/tmp/astra-swift-module-cache}"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/tmp/astra-clang-module-cache}"
mkdir -p "$SWIFTPM_MODULECACHE_OVERRIDE" "$CLANG_MODULE_CACHE_PATH"

cd "$REPO_ROOT"
swift build --disable-sandbox -c "$CONFIGURATION" "${ARCH_FLAGS[@]}" --product Astra
swift build --disable-sandbox -c "$CONFIGURATION" "${ARCH_FLAGS[@]}" --product AstraEnforcer

BIN_DIR="$(swift build --disable-sandbox -c "$CONFIGURATION" "${ARCH_FLAGS[@]}" --show-bin-path)"

rm -rf "$APP_ROOT"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" "$CONTENTS/Library/LaunchAgents"
cp "$BIN_DIR/Astra" "$CONTENTS/MacOS/Astra"
cp "$BIN_DIR/AstraEnforcer" "$CONTENTS/MacOS/AstraEnforcer"
cp "$REPO_ROOT/Assets/Astra.icns" "$CONTENTS/Resources/Astra.icns"
cp "$REPO_ROOT/LICENSE" "$CONTENTS/Resources/LICENSE.txt"
cp "$REPO_ROOT/Config/Astra-Info.plist" "$CONTENTS/Info.plist"
cp "$REPO_ROOT/Config/com.rohitsandadi.astra.enforcer.plist" "$CONTENTS/Library/LaunchAgents/"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $ASTRA_VERSION" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $ASTRA_BUILD_NUMBER" "$CONTENTS/Info.plist"

codesign --force --sign - --options runtime \
  --entitlements "$REPO_ROOT/Config/AstraEnforcer.entitlements" \
  "$CONTENTS/MacOS/AstraEnforcer"
codesign --force --sign - --options runtime \
  --entitlements "$REPO_ROOT/Config/Astra.entitlements" \
  "$APP_ROOT"

codesign --verify --deep --strict --verbose=2 "$APP_ROOT"

# Exercise the helper's side-effect-free startup path after packaging. This
# catches missing embedded Info.plist metadata and an invalid bundle layout
# without registering the LaunchAgent or touching TCC.
if ! "$CONTENTS/MacOS/AstraEnforcer" --diagnose \
  | /usr/bin/plutil -convert xml1 -o /dev/null -- -; then
  echo "Packaged AstraEnforcer failed its diagnostic startup check." >&2
  exit 1
fi
echo "Built $APP_ROOT"
