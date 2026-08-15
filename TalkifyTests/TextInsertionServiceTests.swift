import Testing
@testable import Talkify

struct TextInsertionServiceTests {
  @Test func unreliableAccessibilityEditorsUsePasteInsertion() {
    let bundleIdentifiers = [
      "com.apple.Safari",
      "com.brave.Browser",
      "com.google.Chrome",
      "company.thebrowser.dia",
      "com.todesktop.230313mzl4w4u92",
    ]

    for bundleIdentifier in bundleIdentifiers {
      #expect(TextInsertionService.prefersPaste(
        bundleIdentifier: bundleIdentifier
      ))
    }

    #expect(!TextInsertionService.prefersPaste(
      bundleIdentifier: "com.apple.TextEdit"
    ))
  }
}
