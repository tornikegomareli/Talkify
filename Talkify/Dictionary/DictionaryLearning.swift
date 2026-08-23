import Foundation

enum DictionaryLearning {
  static func learnableEntries(
    rawText: String,
    correctedText: String? = nil,
    editedText: String,
    existing: [DictionaryEntry] = []
  ) -> [DictionaryEntry] {
    let rawTrimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
    let editedTrimmed = editedText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !rawTrimmed.isEmpty, !editedTrimmed.isEmpty else { return [] }
    guard rawTrimmed != editedTrimmed else { return [] }

    if let corrected = correctedText?.trimmingCharacters(in: .whitespacesAndNewlines),
       !corrected.isEmpty,
       corrected != rawTrimmed,
       editedTrimmed == corrected {
      return []
    }

    if isWhitespaceOrPunctuationOnlyChange(from: rawTrimmed, to: editedTrimmed) {
      return []
    }

    if isWholeSentenceRewrite(from: rawTrimmed, to: editedTrimmed) {
      return []
    }

    let candidates = diffEntries(from: rawTrimmed, to: editedTrimmed)
    guard !candidates.isEmpty else { return [] }

    var seen = Set<String>()
    for entry in existing {
      let key = "\(entry.kind.rawValue)|\(entry.hear.lowercased())|\(entry.write.lowercased())"
      seen.insert(key)
    }

    var result: [DictionaryEntry] = []
    for candidate in candidates {
      let key: String
      if candidate.kind == .correction {
        key = "correction|\(candidate.hear.lowercased())|\(candidate.write.lowercased())"
      } else {
        key = "term|\(candidate.write.lowercased())|"
      }
      guard !seen.contains(key) else { continue }
      seen.insert(key)
      result.append(candidate)
    }
    return result
  }

  private static func isWhitespaceOrPunctuationOnlyChange(from raw: String, to edited: String) -> Bool {
    let strippedRaw = raw.lowercased().filter { $0.isLetter || $0.isNumber || $0.isWhitespace }
      .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    let strippedEdited = edited.lowercased().filter { $0.isLetter || $0.isNumber || $0.isWhitespace }
      .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    if strippedRaw == strippedEdited { return true }
    let rawWords = strippedRaw.split(separator: " ")
    let editedWords = strippedEdited.split(separator: " ")
    return rawWords == editedWords
  }

  private static func isWholeSentenceRewrite(from raw: String, to edited: String) -> Bool {
    let rawWords = tokenizeWords(raw)
    let editedWords = tokenizeWords(edited)
    guard !rawWords.isEmpty, !editedWords.isEmpty else { return false }
    let maxCount = max(rawWords.count, editedWords.count)
    guard maxCount > 4 else { return false }
    let lcsLength = longestCommonSubsequenceLength(rawWords, editedWords)
    let similarity = Double(lcsLength) / Double(maxCount)
    return similarity < 0.5
  }

  private static func tokenizeWords(_ text: String) -> [String] {
    text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { !$0.isEmpty }
  }

  private static func longestCommonSubsequenceLength(_ a: [String], _ b: [String]) -> Int {
    var dp = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
    for i in 1...a.count {
      for j in 1...b.count {
        if a[i - 1] == b[j - 1] {
          dp[i][j] = dp[i - 1][j - 1] + 1
        } else {
          dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
        }
      }
    }
    return dp[a.count][b.count]
  }

  private static func diffEntries(from raw: String, to edited: String) -> [DictionaryEntry] {
    let rawTokens = splitPreservingWords(raw)
    let editedTokens = splitPreservingWords(edited)
    let rawWords = rawTokens
    let editedWords = editedTokens

    var i = 0
    var j = 0
    var entries: [DictionaryEntry] = []
    while i < rawWords.count || j < editedWords.count {
      if i < rawWords.count, j < editedWords.count, rawWords[i] == editedWords[j] {
        i += 1
        j += 1
        continue
      }
      let startI = i
      let startJ = j
      var consumedI = 0
      var consumedJ = 0
      let lookahead = 4
      var found = false
      outer: for di in 0...lookahead {
        for dj in 0...lookahead {
          let ni = startI + di
          let nj = startJ + dj
          if ni < rawWords.count, nj < editedWords.count, rawWords[ni] == editedWords[nj] {
            consumedI = di
            consumedJ = dj
            found = true
            break outer
          }
          if ni == rawWords.count, nj == editedWords.count {
            consumedI = rawWords.count - startI
            consumedJ = editedWords.count - startJ
            found = true
            break outer
          }
        }
      }
      if !found {
        consumedI = rawWords.count - startI
        consumedJ = editedWords.count - startJ
      }
      if consumedI == 0, consumedJ == 0 {
        consumedI = 1
        consumedJ = 1
        if startI + consumedI > rawWords.count { consumedI = rawWords.count - startI }
        if startJ + consumedJ > editedWords.count { consumedJ = editedWords.count - startJ }
      }
      let rawSpan = rawTokens[startI..<min(startI + consumedI, rawTokens.count)].joined(separator: " ")
      let editedSpan = editedTokens[startJ..<min(startJ + consumedJ, editedTokens.count)].joined(separator: " ")
      let rawSpanTrimmed = rawSpan.trimmingCharacters(in: .whitespacesAndNewlines)
      let editedSpanTrimmed = editedSpan.trimmingCharacters(in: .whitespacesAndNewlines)
      if !rawSpanTrimmed.isEmpty, !editedSpanTrimmed.isEmpty,
         rawSpanTrimmed.lowercased() != editedSpanTrimmed.lowercased() {
        let wordCount = rawSpanTrimmed.split(whereSeparator: { $0.isWhitespace }).count
        let editedCount = editedSpanTrimmed.split(whereSeparator: { $0.isWhitespace }).count
        if wordCount <= 4, editedCount <= 4 {
          entries.append(.correction(hear: rawSpanTrimmed, write: editedSpanTrimmed))
        }
      } else if rawSpanTrimmed.isEmpty, !editedSpanTrimmed.isEmpty {
        let words = editedSpanTrimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        for word in words where word.count >= 2 && word.rangeOfCharacter(from: .letters) != nil {
          entries.append(.term(word))
        }
      }
      i = startI + consumedI
      j = startJ + consumedJ
      if consumedI == 0, consumedJ == 0 { break }
    }

    var deduped: [DictionaryEntry] = []
    var seenKeys = Set<String>()
    for entry in entries {
      let key = "\(entry.kind.rawValue)|\(entry.hear.lowercased())|\(entry.write.lowercased())"
      if seenKeys.insert(key).inserted {
        deduped.append(entry)
      }
    }
    return deduped
  }

  private static func splitPreservingWords(_ text: String) -> [String] {
    var tokens: [String] = []
    var current = ""
    for char in text {
      if char.isLetter || char.isNumber || char == "'" {
        current.append(char)
      } else if char.isWhitespace || char == "-" {
        if !current.isEmpty {
          tokens.append(current)
          current = ""
        }
      } else {
        if !current.isEmpty {
          tokens.append(current)
          current = ""
        }
      }
    }
    if !current.isEmpty { tokens.append(current) }
    return tokens
  }
}
