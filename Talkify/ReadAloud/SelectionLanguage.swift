import NaturalLanguage

/// Which language a selection is written in.
///
/// Dictation never guesses the language being spoken, because Apple Speech
/// offers no identification and a wrong guess produces fluent nonsense rather
/// than an error (CONTEXT.md). Read Aloud may guess, because it is given text
/// rather than audio, and text identification exists, is on device, and reports
/// how sure it is. Measured on real sentences it returns 1.00; on "ok" it
/// returns 0.29, which is what the floor below is for.
enum SelectionLanguage {
  /// Below this, the answer is treated as no answer. A short or mixed
  /// selection is not worth translating on a coin flip: reading it as it was
  /// written is what Read Aloud did before this existed, and is never wrong.
  static let confidenceFloor = 0.65

  /// The language a selection is written in, or nil when nothing is confident
  /// enough to act on.
  static func detect(in text: String) -> Locale.Language? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let recognizer = NLLanguageRecognizer()
    recognizer.processString(trimmed)
    guard let best = recognizer.languageHypotheses(withMaximum: 1).first,
      best.value >= confidenceFloor
    else { return nil }
    return Locale.Language(identifier: best.key.rawValue)
  }

  /// Whether translating between these two is worth doing at all. Comparing
  /// language codes rather than whole identifiers, so a British voice reading
  /// American text is not a translation.
  static func needsTranslation(from source: Locale.Language, to target: Locale.Language) -> Bool {
    guard let source = source.languageCode?.identifier,
      let target = target.languageCode?.identifier
    else { return false }
    return source != target
  }
}
