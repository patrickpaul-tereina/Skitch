#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Kunkka
# SPDX-License-Identifier: GPL-2.0-only
#
# Cuts a release: bumps the version, commits, tags and pushes.
#
#   scripts/release.sh 1.1.0          # -> tag v1.1.0
#   scripts/release.sh 1.1.0-rc.1     # -> tag v1.1.0-rc.1, published as a
#                                     #    pre-release; project version 1.1.0
#   scripts/release.sh 1.1.0 --yes    # skip the confirmation
#
# Pushing the tag is what triggers .github/workflows/release.yml, which builds
# the universal disk image and publishes it. That workflow refuses to run if the
# tag and the version in CMakeLists.txt disagree — doing both here in one step
# is how they stay in agreement.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CMAKELISTS="$REPO_ROOT/CMakeLists.txt"
RELEASE_BRANCH="${RELEASE_BRANCH:-main}"

say()  { printf '\033[1m==>\033[0m %s\n' "$*"; }
die()  { printf '\033[31m error:\033[0m %s\n' "$*" >&2; exit 1; }

# ------------------------------------------------------------------ arguments

VERSION_ARG="${1:-}"
ASSUME_YES=0
# Written as an if rather than `[[ ... ]] && ASSUME_YES=1`: under `set -e` that
# form kills the script whenever the test is false.
if [[ "${2:-}" == "--yes" || "${2:-}" == "-y" ]]; then
    ASSUME_YES=1
fi

if [[ -z "$VERSION_ARG" ]]; then
    die "Usage: $0 <version> [--yes]
       for example: $0 1.1.0     or     $0 1.1.0-rc.1"
fi

# x.y.z, optionally followed by a pre-release identifier.
if [[ ! "$VERSION_ARG" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
    die "'$VERSION_ARG' is not a version. Expected x.y.z, optionally with a
       pre-release suffix such as 1.1.0-rc.1."
fi

# CMake only understands the numeric part; the suffix lives on the tag.
PROJECT_VERSION="${VERSION_ARG%%-*}"
TAG="v$VERSION_ARG"

cd "$REPO_ROOT"

# ------------------------------------------------------------------ preflight

git rev-parse --git-dir >/dev/null 2>&1 || die "Not a git repository."

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$BRANCH" != "$RELEASE_BRANCH" ]]; then
    die "On branch '$BRANCH', not '$RELEASE_BRANCH'. Releases are cut from
       $RELEASE_BRANCH so CI has already run on the commit being tagged.
       Override with RELEASE_BRANCH=$BRANCH $0 $VERSION_ARG"
fi

if [[ -n "$(git status --porcelain)" ]]; then
    die "The working tree has uncommitted changes. Commit or stash them first —
       the release is built from what is committed, not from what is on disk."
fi

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    die "Tag $TAG already exists. Pick a new version; re-tagging a published
       release would leave people holding a different build under the same name."
fi

say "Fetching to check this branch is current"
git fetch --quiet --tags origin

UPSTREAM="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || echo '')"
if [[ -n "$UPSTREAM" ]]; then
    BEHIND="$(git rev-list --count "HEAD..$UPSTREAM")"
    if [[ "$BEHIND" -gt 0 ]]; then
        die "$BRANCH is $BEHIND commit(s) behind $UPSTREAM. Pull first."
    fi
fi

CURRENT_VERSION="$(awk '
  /^project\(/,/\)/ {
    if (match($0, /VERSION[ \t]+[0-9]+\.[0-9]+\.[0-9]+/)) {
      s = substr($0, RSTART, RLENGTH)
      sub(/VERSION[ \t]+/, "", s)
      print s
      exit
    }
  }' "$CMAKELISTS")"

[[ -n "$CURRENT_VERSION" ]] ||
    die "Could not read VERSION out of the project() call in CMakeLists.txt."

# ---------------------------------------------------------------------- plan

KIND=""
if [[ "$TAG" == *-* ]]; then
    KIND="   (published as a pre-release)"
fi

cat <<EOF

  Version   $CURRENT_VERSION  ->  $PROJECT_VERSION
  Tag       $TAG$KIND
  Commit    $(git rev-parse --short HEAD) on $BRANCH

Pushing the tag starts the release build on GitHub.

EOF

if [[ "$ASSUME_YES" -ne 1 ]]; then
    read -r -p "Go ahead? [y/N] " reply
    [[ "$reply" == "y" || "$reply" == "Y" ]] || { say "Nothing done."; exit 0; }
fi

# --------------------------------------------------------------- version bump

if [[ "$CURRENT_VERSION" != "$PROJECT_VERSION" ]]; then
    # awk to a temp file rather than sed -i, whose syntax differs between the
    # BSD sed on macOS and GNU sed elsewhere.
    TMP="$CMAKELISTS.new.$$"
    awk -v new="$PROJECT_VERSION" '
      !done && /^[ \t]*VERSION[ \t]+[0-9]+\.[0-9]+\.[0-9]+[ \t]*$/ && inproject {
        sub(/[0-9]+\.[0-9]+\.[0-9]+/, new)
        done = 1
      }
      /^project\(/ { inproject = 1 }
      inproject && /\)/ { inproject = 0 }
      { print }
    ' "$CMAKELISTS" > "$TMP"

    if ! grep -q "VERSION $PROJECT_VERSION" "$TMP"; then
        mv "$TMP" "$TMP.failed"
        die "The version bump did not take. Edit CMakeLists.txt by hand; the
       attempt is at $TMP.failed"
    fi

    mv "$TMP" "$CMAKELISTS"
    say "CMakeLists.txt now says $PROJECT_VERSION"

    git add CMakeLists.txt
    git commit -q -m "Skitch $PROJECT_VERSION"
    say "Committed the version bump"
else
    say "CMakeLists.txt already says $PROJECT_VERSION — tagging the current commit"
fi

# ---------------------------------------------------------------- tag and push

git tag -a "$TAG" -m "Skitch $VERSION_ARG"
say "Tagged $TAG"

say "Pushing $BRANCH and $TAG"
git push origin "$BRANCH"
git push origin "$TAG"

REMOTE_URL="$(git remote get-url origin 2>/dev/null || echo '')"
SLUG="$(printf '%s' "$REMOTE_URL" | sed -e 's#^git@github.com:##' -e 's#^https://github.com/##' -e 's#\.git$##')"

cat <<EOF

Release build started. Watch it at:
  https://github.com/$SLUG/actions/workflows/release.yml

When it finishes, the disk image and its checksum are attached to:
  https://github.com/$SLUG/releases/tag/$TAG
EOF
