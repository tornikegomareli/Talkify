import Testing
@testable import Talkify

struct TextInsertionServiceTests {
  @Test func browserEditorsUsePasteInsertion() {
    let browserBundleIdentifiers = [
      "com.apple.Safari",
      "com.brave.Browser",
      "com.google.Chrome",
      "company.thebrowser.dia",
    ]

    for bundleIdentifier in browserBundleIdentifiers {
      #expect(TextInsertionService.prefersPaste(
        bundleIdentifier: bundleIdentifier
      ))
    }

    #expect(!TextInsertionService.prefersPaste(
      bundleIdentifier: "com.apple.TextEdit"
    ))
  }
}
