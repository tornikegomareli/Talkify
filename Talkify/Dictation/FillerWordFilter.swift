import Foundation

/// Removes standalone vocal fillers without rewriting the surrounding dictation.
struct FillerWordFilter {
  private static let expression = try! NSRegularExpression(
    pattern: #"\b(?:uh+|uh+m+|um+|u+m+|ah+|h+m+|m+h+m+|m+m+)(?:[,:;.?!…]+)?(?=\s|$)"#,
    options: [.caseInsensitive]
  )

  func filter(_ text: String) -> String {
    let range = NSRange(text.startIndex..., in: text)
    let removesLeadingFiller = Self.expression.firstMatch(
      in: text,
      options: [],
      range: range
    )?.range.location == 0
    let withoutFillers = Self.expression.stringByReplacingMatches(
      in: text,
      options: [],
      range: range,
      withTemplate: ""
    )

    let filtered = withoutFillers.replacingOccurrences(
      of: #"[ \t]{2,}"#,
      with: " ",
      options: .regularExpression
    )
    .trimmingCharacters(in: .whitespacesAndNewlines)

    guard removesLeadingFiller,
       let firstLetter = filtered.range(of: #"\p{L}"#, options: .regularExpression)
    else {
      return filtered
    }
    return filtered.replacingCharacters(in: firstLetter, with: filtered[firstLetter].uppercased())
  }
}
