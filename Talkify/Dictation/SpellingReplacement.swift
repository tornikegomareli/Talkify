import Foundation

/// One user-authored from→to pair, applied as a whole-word swap after
/// recognition. The Speech Model cannot be taught a word it does not
/// know; this is the list that fixes what it keeps misspelling, and
/// only the words the user typed.
///
/// Whole-word on purpose: a substring swap has no edge, and a list
/// holding "mm" would eat it inside "comment". An incomplete pair —
/// blank `from` or blank `to` — is skipped so a row being typed does
/// not rewrite anything yet.
struct SpellingReplacement: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var from: String
  var to: String
}

enum SpellingReplacements {
  /// Rewrites `text` in one left-to-right pass. Each position offers every
  /// pair the same chance and the longest `from` wins, so a pair for
  /// "git hub" beats one for "git" wherever both fit; equal lengths go
  /// to list order. One pass on purpose: replacing into the running
  /// result would let a later pair rewrite an earlier pair's output, and
  /// the Settings list has no reordering for the user to fix it with.
  ///
  /// Matching is case-insensitive; the replacement is the trimmed `to`
  /// string, so "calman" and "Calman" both become "Kalman" if that is what
  /// the user wrote. A `from` may hold spaces or hyphens — "ex code" and
  /// "e-mail" are what the recognizer produces as often as a single token
  /// is.
  static func apply(_ text: String, using pairs: [SpellingReplacement]) -> String {
    let active = pairs.compactMap { pair -> Pair? in
      let from = pair.from.trimmingCharacters(in: .whitespacesAndNewlines)
      let to = pair.to.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !from.isEmpty, !to.isEmpty else { return nil }
      return Pair(from: from, to: to, length: from.count)
    }
    guard !active.isEmpty, !text.isEmpty else { return text }

    var result = ""
    result.reserveCapacity(text.count)
    var index = text.startIndex
    var previous: Character?
    while index < text.endIndex {
      // A match can only open where a word does, which is also what keeps
      // "mm" out of the middle of "comment".
      if !isWordCharacter(previous),
        let match = longestMatch(in: text, at: index, using: active) {
        result += match.to
        // The boundary the next position sees is the text's, not the
        // replacement's: what was matched stays matched.
        previous = text[text.index(before: match.end)]
        index = match.end
      } else {
        previous = text[index]
        result.append(text[index])
        index = text.index(after: index)
      }
    }
    return result
  }

  private struct Pair {
    let from: String
    let to: String
    let length: Int
  }

  private struct Match {
    let to: String
    let end: String.Index
  }

  private static func longestMatch(
    in text: String,
    at index: String.Index,
    using pairs: [Pair]
  ) -> Match? {
    var best: Match?
    var bestLength = 0
    for pair in pairs where pair.length > bestLength {
      guard
        let end = text.index(index, offsetBy: pair.length, limitedBy: text.endIndex),
        text.compare(pair.from, options: .caseInsensitive, range: index..<end)
          == .orderedSame,
        endsWord(text, at: end)
      else { continue }
      best = Match(to: pair.to, end: end)
      bestLength = pair.length
    }
    return best
  }

  /// Straight and typographic apostrophes, the two that hold a word
  /// together in English.
  private static let apostrophes: Set<Character> = ["'", "\u{2019}"]

  /// Letters, digits, and the apostrophe, so "don't" is one word and a
  /// pair for "don" cannot cut it in half.
  private static func isWordCharacter(_ character: Character?) -> Bool {
    guard let character else { return false }
    return character.isLetter || character.isNumber || apostrophes.contains(character)
  }

  private static func endsWord(_ text: String, at end: String.Index) -> Bool {
    guard end < text.endIndex, isWordCharacter(text[end]) else { return true }
    // A possessive stays attached to the name, because English uses that
    // form for a product and the recognizer misspells it the same way. The
    // 's is left where it is, so it rides the new spelling untouched.
    guard apostrophes.contains(text[end]) else { return false }
    let afterMark = text.index(after: end)
    guard afterMark < text.endIndex, text[afterMark].lowercased() == "s" else {
      return false
    }
    let afterS = text.index(after: afterMark)
    return afterS == text.endIndex || !isWordCharacter(text[afterS])
  }
}
