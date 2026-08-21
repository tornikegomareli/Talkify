import Foundation

/// The two languages one Dictate and Translate session runs between.
///
/// The source is always the primary Dictation Language, so only the target is
/// a setting. Kept as a pair rather than two loose values because everything
/// downstream — the prewarmed session, the HUD tag, the history line — is
/// about the pair and not about either end alone.
struct TranslationPair: Hashable, Sendable {
  let source: Locale.Language
  let target: Locale.Language

  /// What the HUD shows at session start, so someone who forgot their target
  /// can press Escape before speaking rather than after.
  var tag: String { "\(source.shortTag) → \(target.shortTag)" }
}

/// What this Mac can do with a pair. Named here rather than exposing Apple's
/// own status type, so `import Translation` stays inside one file.
enum TranslationAvailability: Sendable, Equatable {
  case installed
  /// Supported, but its model has to be fetched before it can translate.
  case downloadable
  case unsupported
}

enum TranslationFailure: Error, Equatable {
  /// The translator did not answer inside the session's budget.
  case timedOut
  /// The pair cannot be translated on this Mac at all.
  case unsupported
}

extension Locale.Language {
  /// The tag a language is shown as: "EN", "DE", "YUE".
  ///
  /// The whole code, not its first two characters. Truncating gave Cantonese
  /// ("yue") the tag "YU", which is not a language anyone recognises, and it
  /// sat next to Chinese as "ZH" in the same list.
  var shortTag: String {
    guard let code = languageCode?.identifier, !code.isEmpty else { return "" }
    return code.uppercased()
  }
}
