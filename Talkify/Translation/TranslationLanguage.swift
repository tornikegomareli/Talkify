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

/// One language the user could translate into, with what this Mac can do
/// about it right now.
struct TranslationTarget: Identifiable, Hashable, Sendable {
  /// The language code, which is what the preference stores.
  let id: String
  let name: String
  let availability: TranslationAvailability

  /// What the picker shows. A language needing a download says so, rather
  /// than looking identical to one that works and then not working. It cannot
  /// say "on first use", because a model is only ever fetched from Settings.
  var label: String {
    switch availability {
    case .installed: name
    case .downloadable: "\(name) — needs a download"
    case .unsupported: "\(name) — not available"
    }
  }
}

/// What a chosen target can do, for the row under the picker.
enum TranslationModelState: Equatable, Sendable {
  case none
  case ready
  case needsDownload
  case downloading
  case failed
}
