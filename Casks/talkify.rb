cask "talkify" do
  version "0.3.0"
  sha256 "74fc4bbc9060eb0edbb88aca9f8fbe17ad97e5cb039302d91aa82e61c73e8acb"

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
