import Foundation

struct DictionaryEntry: Identifiable, Codable, Hashable, Sendable, Equatable {
  enum Kind: String, Codable, Sendable {
    case term
    case correction
  }

  var id: UUID
  var kind: Kind
  var write: String
  var hear: String
  var isEnabled: Bool

  init(
    id: UUID = UUID(),
    kind: Kind,
    write: String,
    hear: String = "",
    isEnabled: Bool = true
  ) {
    self.id = id
    self.kind = kind
    self.write = write
    self.hear = hear
    self.isEnabled = isEnabled
  }

  static func term(_ word: String, isEnabled: Bool = true) -> DictionaryEntry {
    DictionaryEntry(kind: .term, write: word, isEnabled: isEnabled)
  }

  static func correction(hear: String, write: String, isEnabled: Bool = true) -> DictionaryEntry {
    DictionaryEntry(kind: .correction, write: write, hear: hear, isEnabled: isEnabled)
  }

  var fileLine: String {
    let body = kind == .correction ? "\(hear) -> \(write)" : write
    return isEnabled ? body : "# off: \(body)"
  }

  var normalizedWrite: String {
    write.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var normalizedHear: String {
    hear.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var isValidForFile: Bool {
    let w = write.trimmingCharacters(in: .whitespacesAndNewlines)
    let h = hear.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !w.isEmpty else { return false }
    if w.contains("\n") || w.contains("\r") || w.contains("->") { return false }
    if kind == .term, w.hasPrefix("#") { return false }
    if kind == .correction {
      guard !h.isEmpty else { return false }
      if h.contains("\n") || h.contains("\r") || h.contains("->") { return false }
      if h.hasPrefix("#") { return false }
    }
    return true
  }
}

struct DictionaryWarning: Identifiable, Sendable {
  var id: String { message }
  let message: String

  private static let common: Set<String> = [
    "a", "about", "all", "also", "and", "any", "are", "as", "at", "back", "be", "because",
    "but", "by", "call", "can", "case", "check", "class", "close", "cloud", "code", "come",
    "could", "data", "day", "did", "do", "does", "down", "each", "even", "file", "find",
    "first", "for", "from", "get", "give", "go", "good", "great", "group", "had", "has",
    "have", "he", "her", "here", "him", "his", "how", "if", "in", "into", "is", "it",
    "its", "just", "key", "know", "like", "line", "list", "look", "make", "man", "many",
    "may", "me", "more", "most", "my", "need", "new", "no", "not", "now", "number", "of",
    "off", "on", "one", "only", "open", "or", "other", "our", "out", "over", "page",
    "part", "people", "point", "put", "read", "right", "run", "said", "same", "say",
    "see", "set", "she", "should", "show", "side", "so", "some", "state", "still", "such",
    "take", "team", "test", "than", "that", "the", "their", "them", "then", "there",
    "these", "they", "thing", "think", "this", "time", "to", "two", "type", "up", "us",
    "use", "user", "very", "want", "was", "way", "we", "well", "were", "what", "when",
    "where", "which", "who", "will", "with", "word", "work", "would", "year", "you",
    "your",
  ]

  static func check(_ entry: DictionaryEntry) -> [DictionaryWarning] {
    guard entry.kind == .correction else { return [] }
    let trigger = entry.hear.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trigger.isEmpty else { return [] }
    var warnings: [DictionaryWarning] = []
    let words = trigger.lowercased().split(whereSeparator: { $0 == " " || $0 == "-" })
    if words.count == 1, let only = words.first {
      if common.contains(String(only)) {
        warnings.append(DictionaryWarning(
          message: "\"\(trigger)\" is an ordinary word. This will rewrite every use of it, not just the ones you mean. Consider a longer phrase."
        ))
      } else if only.count <= 3 {
        warnings.append(DictionaryWarning(
          message: "\"\(trigger)\" is very short and will match often. Consider a longer phrase."
        ))
      }
    }
    if entry.write.trimmingCharacters(in: .whitespacesAndNewlines)
      .caseInsensitiveCompare(trigger) == .orderedSame {
      warnings.append(DictionaryWarning(
        message: "This rewrites \"\(trigger)\" to itself, so it will never change anything."
      ))
    }
    return warnings
  }
}
