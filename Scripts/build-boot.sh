#!/bin/sh
# Builds and signs virtlite-boot, the headless tool that boots a guest with no interface.
#
# No bundle involved: entitlements come from the signature, and a bare signed executable carries
# them just as well as an app does. The bundle in build-app.sh is there to make an app, not to
# make the entitlement work.
#
# Usage: Scripts/build-boot.sh [debug|release]
#        .build/arm64-apple-macosx/debug/virtlite-boot --iso path/to.iso --bundle Test.virtlite

set -eu

CONFIGURATION="${1:-debug}"
SIGNING_IDENTITY="${VIRTLITE_SIGNING_IDENTITY:--}"

swift build -c "$CONFIGURATION" --product virtlite-boot

BIN_PATH="$(swift build -c "$CONFIGURATION" --product virtlite-boot --show-bin-path)"
TOOL="$BIN_PATH/virtlite-boot"

codesign --force \
    --sign "$SIGNING_IDENTITY" \
    --entitlements Resources/VirtLite.entitlements \
    --timestamp=none \
    "$TOOL"

echo "signed: $TOOL"
