#!/bin/bash
#
# Cuts a Talkify release: builds Release, packages a DMG, publishes a GitHub
# release with the DMG attached, and points the Homebrew cask at it.
#
#   scripts/release.sh 0.2.0            # build, publish, update the cask
#   scripts/release.sh 0.2.0 --dry-run  # build and package only, publish nothing
#
# The DMG is always named Talkify.dmg so that
# github.com/<repo>/releases/latest/download/Talkify.dmg keeps working — that
# is the URL the landing page's Download button uses.

set -euo pipefail

VERSION="${1:-}"
DRY_RUN=false
[[ "${2:-}" == "--dry-run" ]] && DRY_RUN=true

if [[ -z "$VERSION" ]]; then
  echo "usage: scripts/release.sh <version> [--dry-run]" >&2
  exit 1
fi
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "version must be semver, e.g. 0.2.0 (got '$VERSION')" >&2
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

TAG="v$VERSION"
BUILD_DIR="$REPO_ROOT/.build/release"
ARCHIVE="$BUILD_DIR/Talkify.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
STAGE_DIR="$BUILD_DIR/dmg"
DMG="$BUILD_DIR/Talkify.dmg"
CASK="$REPO_ROOT/Casks/talkify.rb"

step() { printf '\n\033[1;33m▸ %s\033[0m\n' "$1"; }
fail() { printf '\033[1;31m✗ %s\033[0m\n' "$1" >&2; exit 1; }

# ---------------------------------------------------------------- preflight

step "Preflight"
command -v xcodebuild >/dev/null || fail "xcodebuild not found"
command -v hdiutil >/dev/null || fail "hdiutil not found"
if ! $DRY_RUN; then
  command -v gh >/dev/null || fail "gh not found — install the GitHub CLI"
  gh auth status >/dev/null 2>&1 || fail "gh is not authenticated — run 'gh auth login'"
fi

CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$CURRENT_BRANCH" != "main" ]] && ! $DRY_RUN; then
  fail "releases are cut from main (on '$CURRENT_BRANCH')"
fi
if [[ -n "$(git status --porcelain)" ]] && ! $DRY_RUN; then
  fail "working tree is dirty — commit or stash first"
fi
if git rev-parse "$TAG" >/dev/null 2>&1; then
  fail "tag $TAG already exists"
fi
echo "  version $VERSION, tag $TAG, branch $CURRENT_BRANCH"

# ------------------------------------------------------------------- tests

step "Tests"
xcodebuild test \
  -project Talkify.xcodeproj \
  -scheme Talkify \
  -destination 'platform=macOS' \
  -quiet
echo "  suite passed"

# ------------------------------------------------------------------- build

if $DRY_RUN; then
  step "Skipping the version bump (dry run)"
else
  step "Setting version to $VERSION"
  xcrun agvtool new-marketing-version "$VERSION" >/dev/null
  BUILD_NUMBER="$(git rev-list --count HEAD)"
  xcrun agvtool new-version -all "$BUILD_NUMBER" >/dev/null
  echo "  marketing $VERSION, build $BUILD_NUMBER"
fi

step "Archiving Release"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
xcodebuild archive \
  -project Talkify.xcodeproj \
  -scheme Talkify \
  -configuration Release \
  -archivePath "$ARCHIVE" \
  -destination 'generic/platform=macOS' \
  -quiet

APP_IN_ARCHIVE="$ARCHIVE/Products/Applications/Talkify.app"
[[ -d "$APP_IN_ARCHIVE" ]] || fail "archive has no Talkify.app"

mkdir -p "$EXPORT_DIR"
cp -R "$APP_IN_ARCHIVE" "$EXPORT_DIR/Talkify.app"
APP="$EXPORT_DIR/Talkify.app"
echo "  archived $(du -sh "$APP" | cut -f1)"

# Ad-hoc sign if the archive came out unsigned, so Gatekeeper's message is
# "unidentified developer" rather than "damaged".
if ! codesign -dv "$APP" >/dev/null 2>&1; then
  step "Ad-hoc signing (no Developer ID in this build)"
  codesign --force --deep --sign - "$APP"
fi
codesign -dv "$APP" 2>&1 | grep -E "Authority|Signature" | sed 's/^/  /' || true

# --------------------------------------------------------------------- dmg

step "Packaging DMG"
rm -rf "$STAGE_DIR" "$DMG"
mkdir -p "$STAGE_DIR"
cp -R "$APP" "$STAGE_DIR/Talkify.app"
ln -s /Applications "$STAGE_DIR/Applications"
# hdiutil reports "Resource busy" if the freshly copied bundle is still being
# indexed, so give it a few attempts.
for attempt in 1 2 3 4 5; do
  if hdiutil create \
      -volname "Talkify $VERSION" \
      -srcfolder "$STAGE_DIR" \
      -ov -format UDZO \
      "$DMG" >/dev/null 2>&1; then
    break
  fi
  [[ $attempt == 5 ]] && fail "hdiutil could not create the DMG"
  echo "  hdiutil busy, retrying ($attempt)"
  sleep 3
done
hdiutil verify "$DMG" >/dev/null 2>&1 || fail "the DMG failed verification"

# ------------------------------------------------------------- notarization

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  step "Notarizing (profile $NOTARY_PROFILE)"
  xcrun notarytool submit "$DMG" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
  xcrun stapler staple "$DMG"
  echo "  stapled"
else
  step "Notarization skipped"
  cat <<'EOS'
  NOTARY_PROFILE is not set, so this DMG is signed but NOT notarized.
  Gatekeeper will refuse to open it ("Apple cannot check it for malware")
  and `brew install --cask talkify` will install an app that will not launch
  until the user clears quarantine.

  To notarize, store credentials once:
    xcrun notarytool store-credentials talkify-notary \
      --apple-id <apple-id> --team-id 539293JFA3 --password <app-specific-password>
  then re-run with:
    NOTARY_PROFILE=talkify-notary scripts/release.sh <version>
EOS
fi

SHA="$(shasum -a 256 "$DMG" | cut -d' ' -f1)"
echo "  $DMG ($(du -h "$DMG" | cut -f1))"
echo "  sha256 $SHA"

# -------------------------------------------------------------------- cask

step "Updating the Homebrew cask"
[[ -f "$CASK" ]] || fail "missing $CASK"
/usr/bin/sed -i '' \
  -e "s/^  version \".*\"$/  version \"$VERSION\"/" \
  -e "s/^  sha256 \".*\"$/  sha256 \"$SHA\"/" \
  "$CASK"
grep -E "^  (version|sha256)" "$CASK" | sed 's/^/  /'

if $DRY_RUN; then
  step "Dry run — nothing published"
  echo "  DMG:  $DMG"
  echo "  cask updated locally; revert with: git checkout -- Casks/talkify.rb"
  exit 0
fi

# ----------------------------------------------------------------- publish

step "Committing and tagging"
git add Casks/talkify.rb Talkify.xcodeproj/project.pbxproj Talkify/Info.plist 2>/dev/null || true
git commit -q -m "Release $VERSION" || echo "  nothing to commit"
git tag -a "$TAG" -m "Talkify $VERSION"
git push -q origin main
git push -q origin "$TAG"
echo "  pushed $TAG"

step "Publishing the GitHub release"
NOTES_FILE="$BUILD_DIR/notes.md"
PREV_TAG="$(git describe --tags --abbrev=0 "$TAG^" 2>/dev/null || true)"
{
  echo "## Install"
  echo
  echo '```'
  echo "brew tap tornikegomareli/talkify https://github.com/tornikegomareli/Talkify"
  echo "brew install --cask talkify"
  echo '```'
  echo
  echo "Or download **Talkify.dmg** below. Requires macOS 26 on Apple Silicon."
  echo
  echo "## Changes"
  echo
  if [[ -n "$PREV_TAG" ]]; then
    git log --no-merges --pretty='- %s' "$PREV_TAG..$TAG"
  else
    git log --no-merges --pretty='- %s' -20 "$TAG"
  fi
} > "$NOTES_FILE"

gh release create "$TAG" "$DMG" \
  --title "Talkify $VERSION" \
  --notes-file "$NOTES_FILE"

step "Done"
echo "  release:  $(gh release view "$TAG" --json url -q .url)"
echo "  download: https://github.com/tornikegomareli/Talkify/releases/latest/download/Talkify.dmg"
