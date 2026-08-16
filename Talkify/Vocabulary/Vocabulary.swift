import Foundation

/// One Vocabulary Term: a word or short phrase Apple Speech should expect to
/// hear. Stored exactly as the user typed it — casing is part of the term,
/// because whatever the recognizer settles on is what lands in their document.
///
/// A struct rather than a bare String so pronunciation and weighting can join
/// it later without migrating the stored document.
struct VocabularyTerm: Codable, Equatable, Hashable, Identifiable, Sendable {
  var text: String

  var id: String { Vocabulary.foldedKey(for: text) }

  init(text: String) {
    self.text = text
  }
}

struct VocabularyDocument: Codable, Equatable, Sendable {
  static let currentVersion = 1

  var version: Int
  var terms: [VocabularyTerm]

  init(version: Int = currentVersion, terms: [VocabularyTerm] = []) {
    self.version = version
    self.terms = terms
  }
}

/// Why an entered term did not join the Vocabulary. Typed rather than a bare
/// failure so the section can say which rule was hit instead of refusing
/// silently, which reads as a broken text field.
enum VocabularyRejection: Equatable, Sendable {
  case empty
  case tooLong
  case duplicate
  case full
}

enum VocabularyAddOutcome: Equatable, Sendable {
  case added([VocabularyTerm])
  case rejected(VocabularyRejection)
}

/// The pure half of the Vocabulary: normalizing what the user typed, the rules
/// for what may join the list, and the projection Apple Speech consumes.
/// Everything here is a value transformation, so the rules are covered by
/// `VocabularyTests` without touching disk or the Speech framework.
enum Vocabulary {
  /// Apple's documented ceiling for `AnalysisContext.contextualStrings`:
  /// "Limit the total number of phrases across all tags to no more than 100."
  /// Talkify spends every phrase on one tag, so the list cap is that number.
  static let maximumTermCount = 100

  /// Our own guard, with no documented number behind it. Apple asks for
  /// phrases "relatively brief, limiting them to one or two words whenever
  /// possible" and warns that lengthy ones are less likely to be recognized —
  /// guidance, not a limit. This only stops a pasted paragraph from taking a
  /// slot it can never earn back.
  static let maximumTermLength = 128

  /// Trims the ends and collapses interior whitespace runs, so "  Core   Data "
  /// and "Core Data" are one term rather than two that look identical in the
  /// list. Returns an empty string for input that was only whitespace.
  static func normalize(_ raw: String) -> String {
    raw
      .components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
  }

  /// The identity two terms are compared on. Case-insensitive, because
  /// "Talkify" and "talkify" are one acoustic hint and keeping both spends a
  /// slot for nothing. Deliberately *not* diacritic-insensitive: "resume" and
  /// "résumé" are different terms, and telling them apart is the entire reason
  /// someone adds the accented one.
  static func foldedKey(for text: String) -> String {
    normalize(text).lowercased()
  }

  /// Applies every rule for joining the list and returns either the new list
  /// or the reason it was refused. New terms go on top: after typing one into
  /// a list of two hundred, seeing it appear is the confirmation that the add
  /// worked, and alphabetical order would file it somewhere off screen.
  static func adding(_ raw: String, to terms: [VocabularyTerm]) -> VocabularyAddOutcome {
    let text = normalize(raw)

    guard !text.isEmpty else { return .rejected(.empty) }
    guard text.count <= maximumTermLength else { return .rejected(.tooLong) }

    let key = foldedKey(for: text)
    guard !terms.contains(where: { $0.id == key }) else {
      return .rejected(.duplicate)
    }
    guard terms.count < maximumTermCount else { return .rejected(.full) }

    return .added([VocabularyTerm(text: text)] + terms)
  }

  static func removing(_ term: VocabularyTerm, from terms: [VocabularyTerm]) -> [VocabularyTerm] {
    terms.filter { $0.id != term.id }
  }

  /// The list with every rule applied: normalized, stripped of empty and
  /// oversized entries, folded duplicates dropped, and cut to the cap.
  ///
  /// The store runs this over whatever it decodes rather than trusting the
  /// file. A document written by an older build or edited by hand can hold
  /// entries that break things well before they reach Apple Speech: two folded
  /// duplicates give the section repeated `ForEach` identifiers, and removing
  /// either one would take both, since terms are removed by folded key.
  static func canonical(_ terms: [VocabularyTerm]) -> [VocabularyTerm] {
    var seen = Set<String>()
    var canonical: [VocabularyTerm] = []

    for term in terms {
      let text = normalize(term.text)
      guard !text.isEmpty, text.count <= maximumTermLength else { continue }
      guard seen.insert(foldedKey(for: text)).inserted else { continue }
      canonical.append(VocabularyTerm(text: text))
      if canonical.count == maximumTermCount { break }
    }

    return canonical
  }

  /// What the analyzer receives. Canonical by construction, so the list the
  /// section shows and the phrases Apple Speech is given can never disagree.
  static func contextualStrings(for terms: [VocabularyTerm]) -> [String] {
    canonical(terms).map(\.text)
  }
}
