#!/usr/bin/env bash
#
# Installs Skitch.app into /Applications (or a directory you name).
#
#   scripts/install.sh                    # build if needed, install to /Applications
#   scripts/install.sh path/to/Skitch.app # install a specific build
#   DEST=~/Applications scripts/install.sh
#
# Existing copies are moved to the Trash rather than deleted outright, so a bad
# install is always recoverable.

set -euo pipefail

APP_NAME="Skitch"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$REPO_ROOT/build}"
DEST="${DEST:-/Applications}"

say()  { printf '\033[1m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33m warning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31m error:\033[0m %s\n' "$*" >&2; exit 1; }

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
[[ -x "$APP/Contents/MacOS/$APP_NAME" ]] || die "$APP has no executable — is it a complete bundle?"

TARGET="$DEST/$APP_NAME.app"

# --------------------------------------------------------------- preflight

[[ -d "$DEST" ]] || die "Destination $DEST does not exist."
if [[ ! -w "$DEST" ]]; then
    die "No write access to $DEST. Re-run with sudo, or set DEST to somewhere you own:
       DEST=\"\$HOME/Applications\" $0"
fi

# A running copy would keep its old binary mapped and confuse the replace.
if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    say "Quitting the running $APP_NAME…"
    osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        pgrep -x "$APP_NAME" >/dev/null 2>&1 || break
        sleep 0.3
    done
    if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
        warn "$APP_NAME is still running; the replace may fail."
    fi
fi

# ------------------------------------------------- retire any existing copy

RETIRED=""
if [[ -e "$TARGET" ]]; then
    # Never delete outright. Prefer the Trash; otherwise rename in place, which
    # needs no extra permission and always works if the directory is writable.
    if command -v trash >/dev/null 2>&1 && trash "$TARGET" 2>/dev/null; then
        say "Moved the previous $APP_NAME to the Trash."
    else
        RETIRED="$TARGET.old-$(date +%Y%m%d-%H%M%S)"
        mv "$TARGET" "$RETIRED" ||
            die "Could not move $TARGET aside. Remove it yourself, then re-run."
        say "Renamed the previous copy to $(basename "$RETIRED")"
    fi
fi

# ------------------------------------------------------------------ install

say "Installing to $TARGET"
# ditto is the Apple-sanctioned bundle copy: it preserves the bundle layout,
# extended attributes and the code signature.
ditto "$APP" "$TARGET"

# Clear the quarantine flag so Gatekeeper does not block a locally built app.
xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null || true

if ! codesign --verify --strict "$TARGET" 2>/dev/null; then
    warn "Code signature did not verify. The app will still run locally, but
         macOS may re-prompt for Screen Recording access."
fi

say "Installed $APP_NAME $(defaults read "$TARGET/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo '')"

if [[ -n "$RETIRED" ]]; then
    warn "The previous version is still on disk at:
         $RETIRED
         Delete it once you are happy with this build."
fi

cat <<EOF

  Launch it:      open -a $APP_NAME
  Grant capture:  System Settings > Privacy & Security > Screen Recording

Because this build is ad-hoc signed, macOS treats each rebuild as a new app and
will ask for Screen Recording again after you reinstall.
EOF
