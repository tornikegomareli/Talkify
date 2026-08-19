#!/bin/bash
#
# Builds and installs the throwaway input method spike.
#
#   spike/ime/build.sh          # build, install, restart the input method
#   spike/ime/build.sh --clean  # remove it from the system
#
# It installs to ~/Library/Input Methods/, which is a per-user directory and
# needs no privileges. Enabling it is a manual step in System Settings, on
# purpose: that step is part of what the spike is measuring.

set -euo pipefail

NAME="TalkifyIMESpike"
BUNDLE_ID="com.talkify.imespike"
MODE_ID="$BUNDLE_ID.mode"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="$HOME/Library/Input Methods/$NAME.app"
BUILD="$HERE/.build/$NAME.app"

fail() { echo "error: $*" >&2; exit 1; }

if [[ "${1:-}" == "--clean" ]]; then
  pkill -f "$NAME" 2>/dev/null || true
  rm -rf "$DEST"
  echo "removed $DEST"
  echo "Now remove it in System Settings > Keyboard > Input Sources if it is still listed."
  exit 0
fi

rm -rf "$HERE/.build"
mkdir -p "$BUILD/Contents/MacOS" "$BUILD/Contents/Resources"

# Swift 5 language mode: InputMethodKit's headers predate Swift Concurrency and
# do not compile under Swift 6 strict checking. Talkify itself stays on 6; this
# is one more reason the real thing would need its own target.
swiftc \
  -swift-version 5 \
  -target arm64-apple-macos26.0 \
  -framework Cocoa \
  -framework InputMethodKit \
  -o "$BUILD/Contents/MacOS/$NAME" \
  "$HERE/Sources/main.swift"

cat > "$BUILD/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>$NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>Talkify IME Spike</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSBackgroundOnly</key><true/>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>

  <!-- The connection name the process registers, and the controller class the
       system instantiates. The class name is the @objc name, not the Swift one. -->
  <key>InputMethodConnectionName</key><string>TalkifySpike_Connection</string>
  <key>InputMethodServerControllerClass</key><string>TalkifySpikeController</string>
  <!-- Without a declared repertoire the scanner ignores the bundle entirely. -->
  <key>tsInputMethodCharacterRepertoireKey</key>
  <array><string>Latn</string></array>

  <!-- One input mode, visible and on by default, so it appears in the Input
       Sources list after a restart of the input method system. -->
  <key>ComponentInputModeDict</key>
  <dict>
    <key>tsInputModeListKey</key>
    <dict>
      <key>$MODE_ID</key>
      <dict>
        <key>TISInputSourceID</key><string>$MODE_ID</string>
        <key>TISIntendedLanguage</key><string>en</string>
        <key>tsInputModeDefaultStateKey</key><true/>
        <key>tsInputModeIsVisibleKey</key><true/>
        <key>tsInputModePrimaryInScriptKey</key><true/>
        <key>tsInputModeScriptKey</key><string>smRoman</string>
        <key>tsInputModeCharacterRepertoireKey</key>
        <array><string>Latn</string></array>
      </dict>
    </dict>
    <key>tsVisibleInputModeOrderedArrayKey</key>
    <array><string>$MODE_ID</string></array>
  </dict>
</dict>
</plist>
PLIST

# Ad-hoc signature. Enough for a locally built input method; a shipped one would
# need a Developer ID and notarization like the app does.
codesign --force --sign - --timestamp=none "$BUILD" >/dev/null 2>&1 \
  || fail "codesign failed"

pkill -f "$NAME" 2>/dev/null || true
rm -rf "$DEST"
mkdir -p "$HOME/Library/Input Methods"
cp -R "$BUILD" "$DEST"

echo "installed: $DEST"
codesign -dv "$DEST" 2>&1 | grep -E "Identifier|Signature" || true
echo
echo "Next, once only:"
echo "  1. System Settings > Keyboard > Input Sources > Edit > + > English"
echo "  2. Pick 'Talkify IME Spike' and add it"
echo "  3. Switch to it from the input menu in the menu bar"
echo
echo "Then in any app's text field, press F13."
echo "Watch the log with:  log stream --predicate 'eventMessage CONTAINS \"[IMESpike]\"'"
