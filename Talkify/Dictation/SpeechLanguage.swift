import Foundation
import Speech

/// One language Apple Speech can transcribe, as the Language section lists it.
/// `isInstalled` matters to the user: an uninstalled language downloads its
/// model on first use, so the picker says so before they pick it.
struct SpeechLanguage: Identifiable, Equatable, Sendable {
  let locale: Locale
  let name: String
  let isInstalled: Bool

  var id: String { locale.identifier }

  var tag: String { SpeechLanguageCatalog.tag(for: locale) }
}

/// Reads the language list from Apple Speech. Every entry comes from
/// `SpeechTranscriber.supportedLocales`, so the list is whatever this Mac's
/// macOS actually supports rather than a hardcoded table that can drift.
enum SpeechLanguageCatalog {
  /// The tag for the HUD ("EN", "DE", "YUE"), so a session shows which
  /// language is listening. Recognition fails confidently in the wrong
  /// language, which makes this worth the space.
  ///
  /// One definition, shared with the translation pair's tag, so the two can
  /// never disagree about what a language is called.
  static func tag(for locale: Locale) -> String {
    let tag = locale.language.shortTag
    guard tag.isEmpty else { return tag }
    return locale.identifier.prefix(2).uppercased()
  }

  /// The language's own name without its region ("German"), for prose where
  /// the region adds nothing: a HUD line has no room for "German (Germany)".
  static func shortName(for locale: Locale) -> String {
    guard let code = locale.language.languageCode?.identifier,
       let name = Locale.current.localizedString(forLanguageCode: code) else {
      return tag(for: locale)
    }
    return name.localizedCapitalized
  }

  static func available() async -> [SpeechLanguage] {
    let installed = Set(await SpeechTranscriber.installedLocales.map(\.identifier))
    let display = Locale.current

    return await SpeechTranscriber.supportedLocales
      .map { locale in
        SpeechLanguage(
          locale: locale,
          name: name(for: locale, in: display),
          isInstalled: installed.contains(locale.identifier)
        )
      }
      .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }

  /// "German (Germany)" rather than "de_DE": the region matters, because
  /// Apple ships several variants of most of these languages.
  private static func name(for locale: Locale, in display: Locale) -> String {
    guard let code = locale.language.languageCode?.identifier,
       let language = display.localizedString(forLanguageCode: code) else {
      return locale.identifier
    }

    guard let region = locale.region?.identifier,
       let regionName = display.localizedString(forRegionCode: region) else {
      return language.localizedCapitalized
    }

    return "\(language.localizedCapitalized) (\(regionName))"
  }
}
