import Foundation

/// The words a user tells Apple Speech to expect.
///
/// The one accuracy gap a general on-device model cannot close by itself: it
/// has never heard your colleague's name or your product's, so it mishears
/// them every session and no better model fixes that, because the information
/// is not in it. `AnalysisContext.contextualStrings` is where it goes.
///
/// Biasing before the words are heard, rather than rewriting them after. A
/// find-and-replace pass over finished text has no edge to its category and
/// eats real words: "3 mm" becomes "3" the first time "mm" is on the list.
///
/// A value type with static rules, so what may join the list is testable
/// without a Settings window or a recognizer.
enum Vocabulary {
  /// Apple asks for at most 100 phrases across all tags. Talkify spends them
  /// all on one tag, so this is the whole budget.
  static let maximumTermCount = 100

  /// No documented limit behind this one. Apple asks for phrases "relatively
  /// brief", and a term the length of a sentence never matches what anyone
  /// says, so this only stops a pasted paragraph taking a slot.
  static let maximumTermLength = 64

  /// Cleans up one entered term, or returns nil when there is nothing left.
  ///
  /// Casing survives: whatever the recognizer settles on is what lands in the
  /// document, so someone who typed "Talkify" wants that capital.
  static func normalized(_ raw: String) -> String? {
    let collapsed = raw
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !collapsed.isEmpty, collapsed.count <= maximumTermLength else { return nil }
    return collapsed
  }

  /// The list with `term` added, or nil when it cannot join: nothing left after
  /// cleaning, too long, already there, or the list is full.
  ///
  /// Case-insensitive on duplicates because two spellings of one word are one
  /// acoustic hint. Diacritics stay distinct: "resume" and "résumé" are
  /// different words, and telling them apart is why someone added the second.
  static func adding(_ term: String, to terms: [String]) -> [String]? {
    guard let normalized = normalized(term), terms.count < maximumTermCount else { return nil }
    let existing = Set(terms.map { $0.lowercased() })
    guard !existing.contains(normalized.lowercased()) else { return nil }
    return terms + [normalized]
  }

  /// A stored list made safe to use, because UserDefaults holds whatever was
  /// last written and an older build may have written more, longer, or
  /// duplicate terms.
  static func sanitized(_ terms: [String]) -> [String] {
    var seen = Set<String>()
    var result: [String] = []
    for term in terms {
      guard let normalized = normalized(term) else { continue }
      guard seen.insert(normalized.lowercased()).inserted else { continue }
      result.append(normalized)
      if result.count == maximumTermCount { break }
    }
    return result
  }
}
