import Testing
@testable import Talkify

struct SpellingReplacementTests {
  @Test func emptyListLeavesTheTextAlone() {
    #expect(SpellingReplacements.apply("Calman shipped", using: []) == "Calman shipped")
  }

  @Test func swapsAWholeWordRegardlessOfCase() {
    let pairs = [SpellingReplacement(id: "1", from: "Calman", to: "Kalman")]
    #expect(SpellingReplacements.apply("Calman shipped", using: pairs) == "Kalman shipped")
    #expect(SpellingReplacements.apply("calman shipped", using: pairs) == "Kalman shipped")
    #expect(SpellingReplacements.apply("CALMAN shipped", using: pairs) == "Kalman shipped")
  }

  @Test func replacesEveryOccurrence() {
    let pairs = [SpellingReplacement(id: "1", from: "Calman", to: "Kalman")]
    #expect(
      SpellingReplacements.apply("Calman met Calman", using: pairs) == "Kalman met Kalman"
    )
  }

  @Test func doesNotReplaceAWordThatOnlyContainsTheFrom() {
    let pairs = [SpellingReplacement(id: "1", from: "mm", to: "millimetres")]
    #expect(
      SpellingReplacements.apply("leave a comment", using: pairs) == "leave a comment"
    )
  }

  @Test func keepsSurroundingPunctuation() {
    let pairs = [SpellingReplacement(id: "1", from: "Calman", to: "Kalman")]
    #expect(SpellingReplacements.apply("ship Calman.", using: pairs) == "ship Kalman.")
    #expect(SpellingReplacements.apply("Calman, then", using: pairs) == "Kalman, then")
  }

  @Test func skipsAPairWhoseFromIsBlank() {
    let pairs = [SpellingReplacement(id: "1", from: "  ", to: "Kalman")]
    #expect(SpellingReplacements.apply("Calman", using: pairs) == "Calman")
  }

  @Test func skipsAPairWhoseToIsBlank() {
    let pairs = [SpellingReplacement(id: "1", from: "Calman", to: "  ")]
    #expect(SpellingReplacements.apply("Calman shipped", using: pairs) == "Calman shipped")
  }

  @Test func replacesAPossessiveAndKeepsTheSuffix() {
    let pairs = [SpellingReplacement(id: "1", from: "Calman", to: "Kalman")]
    #expect(SpellingReplacements.apply("Calman's launch", using: pairs) == "Kalman's launch")
    #expect(
      SpellingReplacements.apply("Calman\u{2019}s launch", using: pairs)
        == "Kalman\u{2019}s launch"
    )
  }

  @Test func aPairNeverRewritesAnotherPairsOutput() {
    let pairs = [
      SpellingReplacement(id: "1", from: "colour", to: "color"),
      SpellingReplacement(id: "2", from: "color", to: "Color"),
    ]
    #expect(SpellingReplacements.apply("colour", using: pairs) == "color")
    #expect(SpellingReplacements.apply("color", using: pairs) == "Color")
  }

  @Test func swapsAPhraseTheRecognizerSplitUp() {
    let pairs = [SpellingReplacement(id: "1", from: "ex code", to: "Xcode")]
    #expect(SpellingReplacements.apply("open ex code", using: pairs) == "open Xcode")
    #expect(SpellingReplacements.apply("Ex Code's build", using: pairs) == "Xcode's build")
  }

  @Test func swapsAHyphenatedWord() {
    let pairs = [SpellingReplacement(id: "1", from: "e-mail", to: "email")]
    #expect(SpellingReplacements.apply("send an e-mail", using: pairs) == "send an email")
    #expect(SpellingReplacements.apply("e-mailing you", using: pairs) == "e-mailing you")
  }

  @Test func theLongestMatchingPairWins() {
    let pairs = [
      SpellingReplacement(id: "1", from: "git", to: "Git"),
      SpellingReplacement(id: "2", from: "git hub", to: "GitHub"),
    ]
    #expect(SpellingReplacements.apply("git hub repo", using: pairs) == "GitHub repo")
    #expect(SpellingReplacements.apply("git clone", using: pairs) == "Git clone")
  }

  @Test func leavesAContractionWhole() {
    let pairs = [SpellingReplacement(id: "1", from: "don", to: "Don")]
    #expect(SpellingReplacements.apply("don't stop", using: pairs) == "don't stop")
    #expect(SpellingReplacements.apply("don stopped", using: pairs) == "Don stopped")
  }

  @Test func trimsTheStoredEndsBeforeMatching() {
    let pairs = [SpellingReplacement(id: "1", from: " Calman ", to: " Kalman ")]
    #expect(SpellingReplacements.apply("Calman", using: pairs) == "Kalman")
  }
}
