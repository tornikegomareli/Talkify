import Foundation
import Testing
@testable import Talkify

struct VocabularyTests {
  @Test func normalizeTrimsEndsAndCollapsesInteriorWhitespace() {
    #expect(Vocabulary.normalize("  Core   Data \n") == "Core Data")
    #expect(Vocabulary.normalize("Talkify") == "Talkify")
    #expect(Vocabulary.normalize("   \n\t ").isEmpty)
  }

  @Test func addingKeepsTheCasingTheUserTyped() throws {
    let outcome = Vocabulary.adding("Talkify", to: [])
    guard case let .added(terms) = outcome else {
      Issue.record("expected the term to be added, got \(outcome)")
      return
    }
    #expect(terms.map(\.text) == ["Talkify"])
  }

  @Test func addingPutsTheNewestTermFirst() throws {
    var terms: [VocabularyTerm] = []
    for text in ["Sparkle", "SpeechAnalyzer", "NotchIsland"] {
      guard case let .added(updated) = Vocabulary.adding(text, to: terms) else {
        Issue.record("expected \(text) to be added")
        return
      }
      terms = updated
    }
    #expect(terms.map(\.text) == ["NotchIsland", "SpeechAnalyzer", "Sparkle"])
  }

  @Test func addingRejectsWhitespaceOnlyEntries() {
    #expect(Vocabulary.adding("   \n ", to: []) == .rejected(.empty))
  }

  @Test func addingRejectsSomethingLongerThanATerm() {
    let sentence = String(repeating: "a", count: Vocabulary.maximumTermLength + 1)
    #expect(Vocabulary.adding(sentence, to: []) == .rejected(.tooLong))

    let atLimit = String(repeating: "a", count: Vocabulary.maximumTermLength)
    guard case .added = Vocabulary.adding(atLimit, to: []) else {
      Issue.record("a term exactly at the limit should be accepted")
      return
    }
  }

  /// "Talkify" and "talkify" are one acoustic hint; keeping both would spend a
  /// slot for nothing.
  @Test func addingRejectsADuplicateRegardlessOfCasingOrSpacing() {
    let existing = [VocabularyTerm(text: "Core Data")]
    #expect(Vocabulary.adding("core data", to: existing) == .rejected(.duplicate))
    #expect(Vocabulary.adding("  CORE   DATA  ", to: existing) == .rejected(.duplicate))
  }

  /// Deliberately not diacritic-insensitive: telling these two apart is the
  /// whole reason someone adds the accented one.
  @Test func addingTreatsAccentedTermsAsDistinct() throws {
    let existing = [VocabularyTerm(text: "resume")]
    guard case let .added(terms) = Vocabulary.adding("résumé", to: existing) else {
      Issue.record("an accented spelling is its own term")
      return
    }
    #expect(terms.count == 2)
  }

  @Test func addingRejectsOnceTheListIsFull() {
    let full = (0..<Vocabulary.maximumTermCount).map {
      VocabularyTerm(text: "term-\($0)")
    }
    #expect(Vocabulary.adding("one more", to: full) == .rejected(.full))
    // A duplicate is still reported as a duplicate rather than as full: the
    // message should name the rule the user actually hit.
    #expect(Vocabulary.adding("term-0", to: full) == .rejected(.duplicate))
  }

  @Test func removingMatchesOnTheFoldedTerm() {
    let terms = [VocabularyTerm(text: "Core Data"), VocabularyTerm(text: "Sparkle")]
    let remaining = Vocabulary.removing(VocabularyTerm(text: "core data"), from: terms)
    #expect(remaining.map(\.text) == ["Sparkle"])
  }

  /// The document is a plain JSON file a user can edit by hand, and an older
  /// build may have written it under different rules. Nothing invalid should
  /// reach the Speech framework.
  @Test func contextualStringsSanitizeWhatTheDocumentHolds() {
    let terms = [
      VocabularyTerm(text: "  Talkify  "),
      VocabularyTerm(text: "   "),
      VocabularyTerm(text: String(repeating: "b", count: Vocabulary.maximumTermLength + 1)),
      VocabularyTerm(text: "talkify"),
      VocabularyTerm(text: "Core   Data")
    ]

    #expect(Vocabulary.contextualStrings(for: terms) == ["Talkify", "Core Data"])
  }

  @Test func contextualStringsStopAtTheTermCap() {
    let terms = (0..<(Vocabulary.maximumTermCount + 50)).map {
      VocabularyTerm(text: "term-\($0)")
    }
    #expect(Vocabulary.contextualStrings(for: terms).count == Vocabulary.maximumTermCount)
  }

  @Test func contextualStringsAreEmptyForAnEmptyVocabulary() {
    #expect(Vocabulary.contextualStrings(for: []).isEmpty)
  }
}
