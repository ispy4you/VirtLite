#!/bin/sh
# Enforces ARC-01: VirtLiteCore must not depend on Virtualization.framework.
#
# The boundary is what keeps the engine testable in CI without launching a virtual machine.
# It survives only if something checks it, so this runs on every build.

set -eu

if grep -rn --include='*.swift' '^[[:space:]]*import[[:space:]]\+Virtualization' Sources/VirtLiteCore; then
    echo "" >&2
    echo "error: VirtLiteCore imports Virtualization, which breaks ARC-01." >&2
    echo "       Framework-specific code belongs in VirtLiteVZ." >&2
    exit 1
fi

echo "ok: VirtLiteCore boundary intact (ARC-01)"
