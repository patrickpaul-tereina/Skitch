#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Kunkka
# SPDX-License-Identifier: GPL-2.0-only
#
# Builds a distributable drag-to-install disk image.
#
#   scripts/make-dmg.sh                        # -> build/Skitch-<version>.dmg
#   scripts/make-dmg.sh path/to/Skitch.app out/dir
#
# The image holds the app next to a symlink to /Applications, which is the
# drag-here-to-install layout Mac users expect.

set -euo pipefail

APP_NAME="Skitch"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$REPO_ROOT/build}"

say() { printf '\033[1m==>\033[0m %s\n' "$*"; }
die() { printf '\033[31m error:\033[0m %s\n' "$*" >&2; exit 1; }

command -v hdiutil >/dev/null 2>&1 || die "hdiutil not found — this only runs on macOS."

# ---------------------------------------------------------------- source app

APP="${1:-}"
if [[ -z "$APP" ]]; then
    APP="$BUILD_DIR/$APP_NAME.app"
    if [[ ! -d "$APP" ]]; then
        say "No build found — building first."
        cmake -S "$REPO_ROOT" -B "$BUILD_DIR" -DCMAKE_BUILD_TYPE=Release >/dev/null
        cmake --build "$BUILD_DIR" -j"$(sysctl -n hw.ncpu)"
    fi
fi
[[ -d "$APP" ]] || die "$APP does not exist."

OUT_DIR="${2:-$BUILD_DIR}"
mkdir -p "$OUT_DIR"

VERSION="$(defaults read "$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo 1.0.0)"
DMG="$OUT_DIR/$APP_NAME-$VERSION.dmg"

# ------------------------------------------------------------ staging tree

# Staged inside the build directory so the leftovers are disposable build
# output rather than something that needs deleting from a system temp dir.
STAGING="$OUT_DIR/dmg-staging.$$"
mkdir -p "$STAGING"
cleanup() {
    [[ -d "$STAGING" ]] || return 0
    if command -v trash >/dev/null 2>&1 && trash "$STAGING" >/dev/null 2>&1; then
        return 0
    fi
    printf '  (staging left at %s — it is disposable build output)\n' "$STAGING" >&2
}
trap cleanup EXIT

say "Staging $APP_NAME $VERSION"
ditto "$APP" "$STAGING/$APP_NAME.app"
ln -s /Applications "$STAGING/Applications"

# ---------------------------------------------------------------- the image

if [[ -e "$DMG" ]]; then
    mv "$DMG" "$DMG.previous"
fi

say "Building $DMG"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING" \
    -fs HFS+ \
    -format UDZO \
    -imagekey zlib-level=9 \
    -ov \
    "$DMG" >/dev/null

[[ -f "$DMG" ]] || die "hdiutil did not produce $DMG."

say "Verifying"
hdiutil verify "$DMG" >/dev/null || die "The image failed verification."

SIZE="$(du -h "$DMG" | cut -f1 | tr -d ' ')"
say "Done: $DMG ($SIZE)"

cat <<EOF

Open it and drag $APP_NAME onto the Applications shortcut.

This build is ad-hoc signed, not notarised. On this Mac it opens normally. If
you copy the image to another Mac, Gatekeeper will refuse it until that user
right-clicks the app and chooses Open, or runs:
  xattr -dr com.apple.quarantine /Applications/$APP_NAME.app
EOF
