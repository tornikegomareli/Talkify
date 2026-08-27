import Foundation
import Testing
@testable import Talkify

/// What may join the word list. Pure rules, so they hold without a Settings
/// window or a recognizer.
struct VocabularyTests {
  @Test func casingSurvives() {
    // Whatever the recognizer settles on is what lands in the document, so a
    // capital someone typed is part of what they asked for.
    #expect(Vocabulary.normalized("Talkify") == "Talkify")
    #expect(Vocabulary.normalized("  SwiftUI  ") == "SwiftUI")
  }

  @Test func runsOfWhitespaceCollapse() {
    #expect(Vocabulary.normalized("Ada   Lovelace") == "Ada Lovelace")
    #expect(Vocabulary.normalized("\n Ada \t Lovelace \n") == "Ada Lovelace")
  }

  @Test func nothingUsefulIsNotATerm() {
    #expect(Vocabulary.normalized("") == nil)
    #expect(Vocabulary.normalized("   \n\t ") == nil)
  }

  /// A term the length of a sentence never matches what anyone says, so it
  /// only takes a slot from one that would.
  @Test func aPastedParagraphIsRefused() {
    let long = String(repeating: "a", count: Vocabulary.maximumTermLength + 1)
    #expect(Vocabulary.normalized(long) == nil)
    #expect(Vocabulary.adding(long, to: []) == nil)
  }

  /// Two spellings of one word are one acoustic hint.
  @Test func duplicatesAreRefusedWhateverTheCasing() {
    let terms = ["Talkify"]
    #expect(Vocabulary.adding("talkify", to: terms) == nil)
    #expect(Vocabulary.adding("TALKIFY", to: terms) == nil)
  }

  /// "resume" and "résumé" are different words, and telling them apart is the
  /// reason someone added the accented one.
  @Test func accentsAreTheirOwnTerm() {
    #expect(Vocabulary.adding("résumé", to: ["resume"]) == ["resume", "résumé"])
  }

  @Test func theListStopsAtApplesLimit() {
    let full = (1...Vocabulary.maximumTermCount).map { "term\($0)" }
    #expect(full.count == Vocabulary.maximumTermCount)
    #expect(Vocabulary.adding("one more", to: full) == nil)
  }

  @Test func addingKeepsTheOrderTheyWereAdded() {
    var terms: [String] = []
    for word in ["Talkify", "SwiftUI", "Ada"] {
      terms = Vocabulary.adding(word, to: terms) ?? terms
    }
    #expect(terms == ["Talkify", "SwiftUI", "Ada"])
  }

  /// Stored values come from whatever an older build wrote, so they are made
  /// safe on the way in rather than trusted.
  @Test func aStoredListIsRepaired() {
    let stored = [
      "  Talkify  ",
      "talkify",
      "",
      String(repeating: "b", count: Vocabulary.maximumTermLength + 1),
      "Ada Lovelace",
    ]
    #expect(Vocabulary.sanitized(stored) == ["Talkify", "Ada Lovelace"])
  }

  @Test func aStoredListIsCutToTheLimit() {
    let stored = (1...Vocabulary.maximumTermCount + 20).map { "term\($0)" }
    #expect(Vocabulary.sanitized(stored).count == Vocabulary.maximumTermCount)
  }
}
