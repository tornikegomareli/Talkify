cask "talkify" do
  version "0.6.0"
  sha256 "d8ef6114c70bd6e2592bc519a22c3bd128d2f3e1c35318bab236284b0dabce65"

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
