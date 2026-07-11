#!/bin/bash
#
# Apply the undroidwish-arm64 patches to an AndroWish source checkout.
#
# Usage:  ./apply-patches.sh /path/to/androwish
#
# Patches are applied with `git apply` if the target is a git tree, else with
# `patch -p1`. Re-running is safe-ish: already-applied patches are detected and
# skipped.
set -euo pipefail

AW="${1:-}"
if [ -z "$AW" ] || [ ! -d "$AW/undroid" ] || [ ! -d "$AW/jni" ]; then
    echo "usage: $0 /path/to/androwish   (the dir containing undroid/ and jni/)" >&2
    exit 1
fi
HERE="$(cd "$(dirname "$0")" && pwd)"
PATCHES="$HERE/patches"

cd "$AW"
is_git=0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 && is_git=1

for pf in "$PATCHES"/*.patch; do
    name="$(basename "$pf")"
    if [ "$is_git" = 1 ]; then
        if git apply --reverse --check "$pf" >/dev/null 2>&1; then
            echo "skip (already applied): $name"; continue
        fi
        if git apply --check "$pf" >/dev/null 2>&1; then
            git apply "$pf"; echo "applied: $name"
        else
            echo "FAILED (does not apply cleanly): $name" >&2; exit 1
        fi
    else
        if patch -p1 --dry-run --reverse -f <"$pf" >/dev/null 2>&1; then
            echo "skip (already applied): $name"; continue
        fi
        if patch -p1 --dry-run -f <"$pf" >/dev/null 2>&1; then
            patch -p1 <"$pf"; echo "applied: $name"
        else
            echo "FAILED (does not apply cleanly): $name" >&2; exit 1
        fi
    fi
done

# Place the vendored undroidwish-extras (borg/BLE demos, the tcl-ble-osx `ble`
# package + signed helper, and the bare-launch boot script). Patch 10 makes the
# build script copy these from undroid/undroidwish-extras/ into the assets zip.
if [ -d "$HERE/undroidwish-extras" ]; then
    mkdir -p "$AW/undroid/undroidwish-extras"
    cp -Rp "$HERE/undroidwish-extras/." "$AW/undroid/undroidwish-extras/"
    chmod +x "$AW/undroid/undroidwish-extras/ble1.0/bin/ble_helper.bin" 2>/dev/null || true
    echo "placed: undroid/undroidwish-extras/"
fi
echo "done."
