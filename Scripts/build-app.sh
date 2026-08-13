#!/bin/sh
# Assembles VirtLite.app from the SPM build and signs it with the virtualization entitlement.
#
# A bare executable cannot carry entitlements, and without com.apple.security.virtualization
# nothing can start a guest — so this script, not `swift run`, is how the app gets launched
# during development.
#
# Usage: Scripts/build-app.sh [debug|release]

set -eu

CONFIGURATION="${1:-debug}"
SIGNING_IDENTITY="${VIRTLITE_SIGNING_IDENTITY:--}"

swift build -c "$CONFIGURATION" --product VirtLite

BIN_PATH="$(swift build -c "$CONFIGURATION" --product VirtLite --show-bin-path)"
APP="$BIN_PATH/VirtLite.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_PATH/VirtLite" "$APP/Contents/MacOS/VirtLite"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Debug builds also need get-task-allow, or no debugger can attach. SPM applies it to the bare
# executable, but signing the bundle replaces that signature — so it is added back here rather
# than being silently lost.
ENTITLEMENTS="Resources/VirtLite.entitlements"
if [ "$CONFIGURATION" = "debug" ]; then
    ENTITLEMENTS="$BIN_PATH/VirtLite-debug.entitlements"
    plutil -convert xml1 -o "$ENTITLEMENTS" Resources/VirtLite.entitlements
    plutil -insert "com\.apple\.security\.get-task-allow" -bool true "$ENTITLEMENTS"
fi

# Ad-hoc signature by default, which is enough to hold the entitlement locally. Release builds
# override it with a Developer ID through VIRTLITE_SIGNING_IDENTITY.
codesign --force \
    --sign "$SIGNING_IDENTITY" \
    --entitlements "$ENTITLEMENTS" \
    --timestamp=none \
    "$APP"

echo "built:  $APP"
echo "signed: $SIGNING_IDENTITY"
echo
echo "Entitlements in the signed bundle:"
codesign --display --entitlements - --xml "$APP" 2>/dev/null \
    | plutil -convert xml1 -o - - \
    | grep -A1 "com.apple" \
    || echo "  (none — the app will not be able to start a guest)"
