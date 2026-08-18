#!/bin/bash
#
# Prints the Sparkle EdDSA public key this Mac signs updates with, generating
# the key pair on first run.
#
#   scripts/setup-sparkle-keys.sh          # show the public key
#   scripts/setup-sparkle-keys.sh --export # write the private key to a file
#
# Sparkle keeps the private key in the login Keychain, associated with your user
# account, and one key covers every app you ship — Talkify deliberately reuses
# the key that is already there rather than minting a second one. The public
# half belongs in Talkify/Info.plist under SUPublicEDKey and is safe to commit.
#
# Losing the private key means existing installs can never update again: they
# only trust updates signed by the key their copy was built with. Export it once
# and keep it somewhere you will still have in a year.

set -euo pipefail

# generate_keys -x creates the private key under the process umask before the
# chmod below can narrow it. Narrow it first instead, so the file is never
# group- or world-readable, even briefly.
umask 077

fail() { echo "error: $*" >&2; exit 1; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLIST="$REPO_ROOT/Talkify/Info.plist"

TOOLS="$(find "$HOME/Library/Developer/Xcode/DerivedData"/Talkify-*/SourcePackages/artifacts/sparkle/Sparkle/bin \
  -name generate_keys 2>/dev/null | head -1)"
[[ -n "$TOOLS" ]] || fail "Sparkle's tools are missing. Build Talkify once so Xcode fetches the package."

if [[ "${1:-}" == "--export" ]]; then
  OUT="$HOME/talkify-sparkle-private-key.txt"
  [[ -e "$OUT" ]] && fail "$OUT already exists; move it aside first"
  "$TOOLS" -x "$OUT"
  chmod 600 "$OUT"
  echo "Private key written to $OUT"
  echo "Store it in your password manager, then delete the file."
  exit 0
fi

# -p prints the public key and never overwrites an existing private key. The
# Keychain may prompt for access the first time.
PUBLIC_KEY="$("$TOOLS" -p 2>/dev/null || true)"

if [[ -z "$PUBLIC_KEY" ]]; then
  echo "No signing key found. Generating one in the login Keychain…"
  "$TOOLS"
  PUBLIC_KEY="$("$TOOLS" -p)"
fi

echo "Public key: $PUBLIC_KEY"

IN_PLIST="$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$PLIST" 2>/dev/null || true)"
if [[ "$IN_PLIST" == "$PUBLIC_KEY" ]]; then
  echo "Talkify/Info.plist already carries this key."
else
  echo
  echo "Talkify/Info.plist has: ${IN_PLIST:-<nothing>}"
  echo "Update it so the two match, or updates will fail verification:"
  echo "  /usr/libexec/PlistBuddy -c \"Set :SUPublicEDKey $PUBLIC_KEY\" \"$PLIST\""
  exit 1
fi
