cask "talkify" do
  version "0.4.1"
  sha256 "7a331f474ba383c8a4c6abef774da056a4486f6e04287d4dc83e9024b177a16b"

  url "https://github.com/tornikegomareli/Talkify/releases/download/v#{version}/Talkify.dmg",
      verified: "github.com/tornikegomareli/Talkify/"
  name "Talkify"
  desc "Lightning-fast, local first voice dictation from the notch"
  homepage "https://github.com/tornikegomareli/Talkify"

  depends_on macos: :tahoe
  depends_on arch: :arm64

  app "Talkify.app"

  uninstall quit: "com.tgomareli.Talkify"

  zap trash: [
    "~/Library/Application Support/Talkify",
    "~/Library/Preferences/com.tgomareli.Talkify.plist",
    "~/Library/Saved Application State/com.tgomareli.Talkify.savedState",
  ]

  caveats do
    <<~EOS
      Talkify needs Microphone, Speech Recognition, Accessibility and Input
      Monitoring permissions. It asks for them on first launch — dictation
      reads keys globally and inserts text into other apps.
    EOS
  end
end
