#!/bin/bash
#
# Cuts a Talkify release: builds Release, packages a DMG, publishes a GitHub
# release with the DMG attached, and points the Homebrew cask at it.
#
#   scripts/release.sh 0.2.0            # build, publish, update the cask
#   scripts/release.sh 0.2.0 --dry-run  # build and package only, publish nothing
#
# The update-signing public key is compared against the last tagged release
# before anything is built. Changing it orphans every existing install, so a
# deliberate rotation has to say so:
#   scripts/release.sh 0.3.0 --confirm-key-rotation
#
# Two copies of the same DMG ship with every release. Talkify-vX.Y.Z.dmg is the
# one people download, so the file in their Downloads folder says which version
# it is. Talkify.dmg is a byte-identical copy that keeps
# github.com/<repo>/releases/latest/download/Talkify.dmg resolving — the
# Homebrew cask, the README and the landing page's fallback all use that URL.
#
# Notarization uses a notarytool keychain profile, shared with Camus:
#   NOTARY_PROFILE   keychain profile name  (default: camus-notary)
#   SKIP_NOTARIZE=1  sign and package without notarizing (local testing only)
#
# The landing page names the current release, so it is rebuilt and uploaded
# once the release exists:
#   LANDING_REPO     path to the talkify-landing checkout
#                    (default: ../talkify-landing; skipped if it is missing)

set -euo pipefail

VERSION="${1:-}"
DRY_RUN=false
CONFIRM_KEY_ROTATION=false
shift || true
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --confirm-key-rotation) CONFIRM_KEY_ROTATION=true ;;
    *) echo "unknown option: $arg" >&2; exit 1 ;;
  esac
done

if [[ -z "$VERSION" ]]; then
  echo "usage: scripts/release.sh <version> [--dry-run] [--confirm-key-rotation]" >&2
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
DMG="$BUILD_DIR/Talkify-$TAG.dmg"
# The stable-URL copy, made after the versioned one is signed and stapled.
STABLE_DMG="$BUILD_DIR/Talkify.dmg"
# Sparkle needs its own directory holding only the update ZIP.
SPARKLE_DIR="$BUILD_DIR/sparkle"
SPARKLE_ZIP="$SPARKLE_DIR/Talkify-$TAG.zip"
APPCAST="$REPO_ROOT/appcast.xml"
# Hand-written release notes for this version, used instead of the commit log.
CURATED_NOTES="$REPO_ROOT/docs/release-notes/$VERSION.md"
CASK="$REPO_ROOT/Casks/talkify.rb"
TEAM_ID="539293JFA3"
NOTARY_PROFILE="${NOTARY_PROFILE:-camus-notary}"
SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application: Techzy LLC ($TEAM_ID)}"
ENTITLEMENTS="$REPO_ROOT/Talkify.entitlements"
# The landing page's checkout, deployed after the release so the site names
# this version. Only a sibling clone by default; override to point elsewhere.
LANDING_REPO="${LANDING_REPO:-$REPO_ROOT/../talkify-landing}"

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

# Check the notary credentials before spending minutes on a build.
if [[ "${SKIP_NOTARIZE:-0}" == "1" ]]; then
  echo "  SKIP_NOTARIZE=1 — the DMG will be signed but not notarized"
elif xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  echo "  notary profile '$NOTARY_PROFILE' ready"
else
  fail "notarytool profile '$NOTARY_PROFILE' not found. Store it once with:
    xcrun notarytool store-credentials \"$NOTARY_PROFILE\" \\
      --apple-id <apple-id> --team-id $TEAM_ID --password <app-specific-password>
  or re-run with SKIP_NOTARIZE=1 to skip notarization."
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

# The public key every installed copy checks updates against. If it changes,
# those copies stop trusting anything signed with the new one, and a key
# swapped in by someone else would be trusted by every install from here on.
# Neither is something to discover after publishing.
read_public_key() {
  /usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" /dev/stdin <<<"$1" 2>/dev/null || true
}
CURRENT_KEY="$(read_public_key "$(cat "$REPO_ROOT/Talkify/Info.plist")")"
[[ -n "$CURRENT_KEY" ]] || fail "Talkify/Info.plist has no SUPublicEDKey"

PREVIOUS_TAG="$(git tag --list 'v*' --sort=-v:refname | head -1)"
if [[ -z "$PREVIOUS_TAG" ]]; then
  echo "  no previous tag to compare the update key against (first release)"
elif PREVIOUS_PLIST="$(git show "$PREVIOUS_TAG:Talkify/Info.plist" 2>/dev/null)"; then
  PREVIOUS_KEY="$(read_public_key "$PREVIOUS_PLIST")"
  if [[ -z "$PREVIOUS_KEY" ]]; then
    echo "  $PREVIOUS_TAG carried no SUPublicEDKey; nothing to compare"
  elif [[ "$CURRENT_KEY" == "$PREVIOUS_KEY" ]]; then
    echo "  update key unchanged since $PREVIOUS_TAG"
  elif $CONFIRM_KEY_ROTATION; then
    echo "  update key CHANGED since $PREVIOUS_TAG, confirmed by flag"
    echo "    was: $PREVIOUS_KEY"
    echo "    now: $CURRENT_KEY"
  else
    fail "SUPublicEDKey changed since $PREVIOUS_TAG.
    was: $PREVIOUS_KEY
    now: $CURRENT_KEY
  Every existing install trusts the old key and will refuse updates signed
  with the new one. If this is a deliberate rotation, re-run with
  --confirm-key-rotation. If it is not, find out who changed it."
  fi
else
  echo "  $PREVIOUS_TAG has no Info.plist; nothing to compare"
fi

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
  # Written straight into the project rather than through agvtool. Since the
  # target gained a real Info.plist for Sparkle, agvtool reads an empty
  # CFBundleShortVersionString from it and silently leaves MARKETING_VERSION
  # alone, which shipped an app that called itself 0.1.0.
  BUILD_NUMBER="$(git rev-list --count HEAD)"
  /usr/bin/sed -i '' \
    -e "s/^\([[:space:]]*\)MARKETING_VERSION = .*;$/\1MARKETING_VERSION = $VERSION;/" \
    -e "s/^\([[:space:]]*\)CURRENT_PROJECT_VERSION = .*;$/\1CURRENT_PROJECT_VERSION = $BUILD_NUMBER;/" \
    Talkify.xcodeproj/project.pbxproj

  # Every configuration must agree, or Debug and Release disagree about what
  # version is running.
  STRAY="$(grep -c "MARKETING_VERSION = $VERSION;" Talkify.xcodeproj/project.pbxproj || true)"
  TOTAL="$(grep -c "MARKETING_VERSION = " Talkify.xcodeproj/project.pbxproj || true)"
  [[ "$STRAY" == "$TOTAL" ]] || fail "only $STRAY of $TOTAL MARKETING_VERSION entries became $VERSION"
  echo "  marketing $VERSION, build $BUILD_NUMBER ($TOTAL configurations)"
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

if ! $DRY_RUN; then
  BUILT_SHORT="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
    "$APP/Contents/Info.plist" 2>/dev/null || echo "")"
  BUILT_BUILD="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" \
    "$APP/Contents/Info.plist" 2>/dev/null || echo "")"
  [[ "$BUILT_SHORT" == "$VERSION" ]] \
    || fail "the built app reports version '$BUILT_SHORT', not $VERSION"
  echo "  reports $BUILT_SHORT ($BUILT_BUILD)"
fi

# Ad-hoc sign if the archive came out unsigned, so Gatekeeper's message is
# "unidentified developer" rather than "damaged".
if ! codesign -dv "$APP" >/dev/null 2>&1; then
  step "Ad-hoc signing (no Developer ID in this build)"
  codesign --force --deep --sign - "$APP"
fi
codesign -dv "$APP" 2>&1 | grep -E "Authority|Signature" | sed 's/^/  /' || true

# ----------------------------------------------------------------- resigning

# Sparkle ships prebuilt helpers inside its framework — Updater.app, Autoupdate
# and two XPC services — and Xcode does not re-sign the contents of a prebuilt
# framework. They arrive ad-hoc signed with no team and no secure timestamp,
# which Apple's notary service rejects outright.
#
# codesign seals a bundle by hashing its contents, so this runs strictly
# inside-out: helpers, then the framework, then the app. Signing the app first
# would invalidate its seal the moment a helper changed.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
if [[ -d "$SPARKLE" ]]; then
  if security find-identity -v -p codesigning 2>/dev/null | grep -q "$TEAM_ID"; then
    step "Re-signing Sparkle's helpers"
    # Sparkle's helpers carry empty entitlement dictionaries, so they are signed
    # without any.
    for target in \
      "$SPARKLE/Versions/B/XPCServices/Downloader.xpc" \
      "$SPARKLE/Versions/B/XPCServices/Installer.xpc" \
      "$SPARKLE/Versions/B/Updater.app" \
      "$SPARKLE/Versions/B/Autoupdate" \
      "$SPARKLE"; do
      [[ -e "$target" ]] || continue
      codesign --force --options runtime --timestamp \
        --sign "$SIGN_IDENTITY" "$target" 2>&1 | sed 's/^/  /'
    done

    # The app MUST be re-signed with its entitlements. codesign --force replaces
    # the signature wholesale and drops any entitlements it is not given, and
    # under the hardened runtime an app without com.apple.security.device.audio-input
    # can never be granted the microphone: the prompt appears and the toggle
    # does nothing. v0.3.0 shipped that way.
    [[ -f "$ENTITLEMENTS" ]] || fail "missing $ENTITLEMENTS"
    codesign --force --options runtime --timestamp \
      --entitlements "$ENTITLEMENTS" \
      --sign "$SIGN_IDENTITY" "$APP" 2>&1 | sed 's/^/  /'

    # Every nested binary must now carry the team, or notarization fails again
    # after the DMG and the notary round-trip have already been paid for.
    codesign --verify --deep --strict "$APP" || fail "the re-signed app fails verification"

    # The output is captured rather than piped into grep -q: with pipefail set,
    # grep exiting early on a match kills codesign with SIGPIPE and the pipeline
    # reports failure for a binary that is in fact signed correctly.
    for nested in \
      "$SPARKLE/Versions/B/XPCServices/Downloader.xpc" \
      "$SPARKLE/Versions/B/XPCServices/Installer.xpc" \
      "$SPARKLE/Versions/B/Updater.app" \
      "$SPARKLE/Versions/B/Autoupdate" \
      "$SPARKLE" \
      "$APP"; do
      [[ -e "$nested" ]] || continue
      INFO="$(codesign -dvv "$nested" 2>&1 || true)"
      [[ "$INFO" == *"TeamIdentifier=$TEAM_ID"* ]] \
        || fail "$(basename "$nested") is not signed with team $TEAM_ID"
      [[ "$INFO" == *"flags=0x10000(runtime)"* || "$INFO" == *"runtime"* ]] \
        || fail "$(basename "$nested") is missing the hardened runtime"
    done
    SIGNED_ENTITLEMENTS="$(codesign -d --entitlements :- "$APP" 2>/dev/null || true)"
    [[ "$SIGNED_ENTITLEMENTS" == *"com.apple.security.device.audio-input"* ]] \
      || fail "the signed app has no microphone entitlement — dictation would never work"
    echo "  helpers, framework and app signed with $TEAM_ID, entitlements intact"
  else
    echo "  no Developer ID identity — Sparkle's helpers stay ad-hoc signed"
    echo "  (notarization will reject this build)"
  fi
fi

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

# Sign the container too, so Gatekeeper can vouch for the DMG itself and not
# only the app inside. This must happen BEFORE notarization: signing a stapled
# DMG rewrites the file and throws the ticket away.
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$TEAM_ID"; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
  echo "  container signed"
else
  echo "  no Developer ID identity found — leaving the container unsigned"
fi

# ------------------------------------------------------------- notarization

if [[ "${SKIP_NOTARIZE:-0}" == "1" ]]; then
  step "Notarization skipped (SKIP_NOTARIZE=1)"
  echo "  This DMG is signed but NOT notarized: Gatekeeper will refuse to open"
  echo "  it, and a brew install will land an app that cannot launch."
else
  step "Notarizing with profile '$NOTARY_PROFILE'"
  xcrun notarytool submit "$DMG" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  spctl -a -t open --context context:primary-signature -v "$DMG" 2>&1 | sed 's/^/  /'
  echo "  notarized and stapled"
fi

SHA="$(shasum -a 256 "$DMG" | cut -d' ' -f1)"
echo "  $DMG ($(du -h "$DMG" | cut -f1))"
echo "  sha256 $SHA"

# Copied after signing, notarizing and stapling, so the stable-URL asset is the
# same bytes with the same ticket. The cask's checksum covers both.
cp "$DMG" "$STABLE_DMG"
echo "  $STABLE_DMG (copy for the latest-download URL)"

# ----------------------------------------------------------------- sparkle

# Sparkle updates from a ZIP, not the DMG: it is what BinaryDelta and
# generate_appcast expect, and it unpacks without mounting anything.
#
# Notarizing the DMG notarizes the app inside it, so the app can be stapled
# directly from Apple's records — no second submission and no extra wait. A
# stapled app validates with no network, which matters on a laptop that wakes
# up, updates, and relaunches before Wi-Fi is back.
step "Packaging the Sparkle update"
if [[ "${SKIP_NOTARIZE:-0}" != "1" ]]; then
  xcrun stapler staple "$APP" && echo "  app stapled"
fi

rm -rf "$SPARKLE_DIR"
mkdir -p "$SPARKLE_DIR"
# ditto keeps the bundle's symlinks and resource forks intact; `zip` does not,
# and a mangled bundle fails its signature check after the update lands.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$SPARKLE_ZIP"
echo "  $(basename "$SPARKLE_ZIP") ($(du -h "$SPARKLE_ZIP" | cut -f1))"

SPARKLE_BIN="$(find "$HOME/Library/Developer/Xcode/DerivedData"/Talkify-*/SourcePackages/artifacts/sparkle/Sparkle/bin \
  -name generate_appcast 2>/dev/null | head -1)"
[[ -n "$SPARKLE_BIN" ]] || fail "Sparkle's tools are missing. Build once in Xcode to fetch them."
SPARKLE_BIN="$(dirname "$SPARKLE_BIN")"

# The private key lives in the login Keychain (see scripts/setup-sparkle-keys.sh),
# so the tools find it without a key file on disk. The Keychain WILL prompt for
# access the first time and blocks until it is answered — choose Always Allow so
# later releases run unattended. This step cannot be run headlessly until then.
# Only the ZIP is in SPARKLE_DIR: generate_appcast refuses two archives that
# report the same bundle version, which the DMG would.
"$SPARKLE_BIN/generate_appcast" \
  --download-url-prefix "https://github.com/tornikegomareli/Talkify/releases/download/$TAG/" \
  --link "https://usetalkify.app" \
  --full-release-notes-url "https://github.com/tornikegomareli/Talkify/releases" \
  --maximum-versions 5 \
  -o "$APPCAST" \
  "$SPARKLE_DIR"

[[ -s "$APPCAST" ]] || fail "generate_appcast produced no appcast"
grep -q "sparkle:edSignature" "$APPCAST" || fail "the appcast has no EdDSA signature"
echo "  appcast written, signature present"

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
  echo "  copy: $STABLE_DMG"
  echo "  ZIP:  $SPARKLE_ZIP"
  echo "  appcast: $APPCAST (uncommitted)"
  echo "  cask updated locally; revert with: git checkout -- Casks/talkify.rb"
  exit 0
fi

# ----------------------------------------------------------------- publish

step "Committing and tagging"
# Stage each path that exists: a single git add with one missing pathspec
# fails wholesale and would silently stage nothing.
for path in Casks/talkify.rb Talkify.xcodeproj/project.pbxproj Talkify/Info.plist appcast.xml; do
  [[ -e "$path" ]] && git add "$path"
done
if git diff --cached --quiet; then
  echo "  nothing staged — version and cask already match"
else
  git commit -q -m "Release $VERSION"
  echo "  committed $(git diff --name-only HEAD~1 HEAD | tr '\n' ' ')"
fi
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
  # Homebrew 6 will not load a cask from a third-party tap until it is trusted.
  echo "brew trust --tap tornikegomareli/talkify"
  echo "brew install --cask talkify"
  echo '```'
  echo
  echo "Or download **Talkify.dmg** below. Requires macOS 26 on Apple Silicon."
  echo
  echo "## Changes"
  echo
  # Written notes win when they exist: a commit log says what changed in the
  # code, which is not the same as what changed for the person reading it.
  if [[ -f "$CURATED_NOTES" ]]; then
    cat "$CURATED_NOTES"
  elif [[ -n "$PREV_TAG" ]]; then
    git log --no-merges --pretty='- %s' "$PREV_TAG..$TAG"
  else
    git log --no-merges --pretty='- %s' -20 "$TAG"
  fi
} > "$NOTES_FILE"

# The ZIP ships alongside the DMG because the appcast's enclosure URL points
# at it. Without it every existing install would poll a 404 forever.
#
# appcast.xml goes up too, as the immutable copy of what this tag published.
# The live SUFeedURL still reads the one on main, which anyone with write
# access could rewrite; this asset is what that claim can be checked against.
gh release create "$TAG" "$DMG" "$STABLE_DMG" "$SPARKLE_ZIP" "$APPCAST" \
  --title "Talkify $VERSION" \
  --notes-file "$NOTES_FILE"

# The feed is only live once the appcast on main names a release that exists,
# so check the URL Sparkle will actually poll rather than assuming.
step "Verifying the update feed"
FEED="https://raw.githubusercontent.com/tornikegomareli/Talkify/main/appcast.xml"
if curl -fsS "$FEED" | grep -q "$TAG"; then
  echo "  $FEED serves $TAG"
else
  echo "  WARNING: $FEED does not mention $TAG yet."
  echo "  raw.githubusercontent.com caches for a few minutes; re-check before"
  echo "  announcing, and confirm appcast.xml was pushed to main."
fi
ENCLOSURE="$(grep -o 'url="[^"]*\.zip"' "$APPCAST" | head -1 | cut -d'"' -f2)"
if [[ -n "$ENCLOSURE" ]] && curl -fsSI "$ENCLOSURE" >/dev/null 2>&1; then
  echo "  enclosure reachable"
else
  echo "  WARNING: the appcast enclosure is not reachable: $ENCLOSURE"
fi

# The landing page reads the latest release when it builds, so it only learns
# about this one when it is rebuilt and re-uploaded. The Pages project is
# direct upload rather than git-connected, so there is no deploy hook to fire:
# the files have to be built here and pushed. Nothing below is fatal — the
# release is already published, and a landing page one version behind is worth
# less than a script that exits non-zero after doing the irreversible part.
step "Redeploying the landing page"
deploy_landing() {
  # Asking git rather than looking for a .git directory: in a worktree .git is
  # a file, and this repo is worked on in worktrees.
  git -C "$LANDING_REPO" rev-parse --git-dir >/dev/null 2>&1 || {
    echo "  no landing checkout at $LANDING_REPO — skipping."
    return 1
  }

  local branch
  branch="$(git -C "$LANDING_REPO" rev-parse --abbrev-ref HEAD)"
  [[ "$branch" == "main" ]] || {
    echo "  landing checkout is on '$branch', not main — skipping."
    return 1
  }

  # Tracked changes only. The landing repo carries an AGENTS.md that Next
  # rewrites on every `next dev`, so counting untracked files would block
  # every release.
  [[ -z "$(git -C "$LANDING_REPO" status --porcelain --untracked-files=no)" ]] || {
    echo "  landing checkout has uncommitted changes — skipping."
    return 1
  }

  [[ "$(git -C "$LANDING_REPO" rev-list --count '@{upstream}..HEAD' 2>/dev/null || echo 0)" == "0" ]] || {
    echo "  landing checkout has unpushed commits — skipping."
    return 1
  }

  (cd "$LANDING_REPO" && npm run build >/dev/null) || {
    echo "  the landing build failed — skipping the upload."
    return 1
  }
  (cd "$LANDING_REPO" && npx wrangler pages deploy out \
    --project-name=talkify --branch=main >/dev/null) || {
    echo "  wrangler could not upload the build."
    return 1
  }

  echo "  usetalkify.app rebuilt; it now names $VERSION"
  return 0
}

if ! deploy_landing; then
  echo "  usetalkify.app keeps naming the previous version until it is"
  echo "  redeployed. Its Download button still resolves to this release."
  echo "  To do it by hand:"
  echo "    cd $LANDING_REPO && npm run build"
  echo "    npx wrangler pages deploy out --project-name=talkify --branch=main"
fi

step "Done"
echo "  release:  $(gh release view "$TAG" --json url -q .url)"
echo "  download: https://github.com/tornikegomareli/Talkify/releases/latest/download/Talkify.dmg"
echo "  feed:     $FEED"
