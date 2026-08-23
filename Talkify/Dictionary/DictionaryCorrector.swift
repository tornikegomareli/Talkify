import Foundation

struct AppliedCorrection: Codable, Hashable, Sendable {
  let from: String
  let to: String
  let count: Int
}

struct DictionaryCorrector: Sendable {
  private let rules: [Rule]

  private struct Rule: Sendable {
    let regex: NSRegularExpression
    let replacement: String
    let trigger: String
  }

  init(entries: [DictionaryEntry]) {
    let corrections = entries
      .filter { $0.isEnabled && $0.kind == .correction }
      .filter { !$0.hear.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      .sorted { $0.hear.count > $1.hear.count }

    rules = corrections.compactMap { entry in
      guard let regex = Self.makeRegex(for: entry.hear) else { return nil }
      return Rule(
        regex: regex,
        replacement: NSRegularExpression.escapedTemplate(for: entry.write),
        trigger: entry.hear
      )
    }
  }

  var isEmpty: Bool { rules.isEmpty }

  func apply(to text: String) -> (text: String, applied: [AppliedCorrection]) {
    guard !rules.isEmpty, !text.isEmpty else { return (text, []) }
    var result = text.precomposedStringWithCanonicalMapping
    var applied: [AppliedCorrection] = []
    for rule in rules {
      let range = NSRange(result.startIndex..., in: result)
      let matches = rule.regex.numberOfMatches(in: result, range: range)
      guard matches > 0 else { continue }
      let firstMatch = rule.regex.firstMatch(in: result, range: range)
      let heard = firstMatch
        .flatMap { Range($0.range, in: result) }
        .map { String(result[$0]) } ?? rule.trigger
      result = rule.regex.stringByReplacingMatches(
        in: result,
        range: range,
        withTemplate: rule.replacement
      )
      applied.append(AppliedCorrection(
        from: heard,
        to: rule.replacement.replacingOccurrences(of: "\\", with: ""),
        count: matches
      ))
    }
    return (result, applied)
  }

  private static func makeRegex(for trigger: String) -> NSRegularExpression? {
    let parts = trigger
      .precomposedStringWithCanonicalMapping
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "\t" })
      .map { NSRegularExpression.escapedPattern(for: String($0)) }
    guard !parts.isEmpty else { return nil }
    let body = parts.joined(separator: "[\\s\\-]*")
    let pattern = "(?<![\\p{L}\\p{N}])\(body)(?![\\p{L}\\p{N}])"
    return try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
  }
}

extension DictionaryCorrector {
  static let biasLimit = 40

  static func biasPhrases(from entries: [DictionaryEntry]) -> [String] {
    var seen = Set<String>()
    var phrases: [String] = []
    for entry in entries where entry.isEnabled {
      let phrase = entry.write.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !phrase.isEmpty, seen.insert(phrase.lowercased()).inserted else { continue }
      phrases.append(phrase)
      if phrases.count == biasLimit { break }
    }
    return phrases
  }
}
