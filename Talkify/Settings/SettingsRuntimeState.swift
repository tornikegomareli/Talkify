import Observation

/// Live app state the Settings surface reflects but does not own: whether a
/// Direct Dictation session is active (drives the changes-apply-next-session
/// notice). The composition root updates it from the dictation controller.
@MainActor
@Observable
final class SettingsRuntimeState {
  var isDictating: Bool

  /// Language models currently downloading, as locale identifier to progress
  /// (0…1). A language picked before its model exists downloads in the
  /// background, and the Language section says so rather than looking idle.
  var languageDownloads: [String: Double] = [:]

  /// Every language the chosen source can translate into, with what this Mac
  /// can do about each. Probed when the languages change, because the answer
  /// depends on which models are installed.
  var translationTargets: [TranslationTarget] = []

  /// What the chosen target can do right now, for the row under the picker.
  var translationModelState: TranslationModelState = .none

  /// Asks the app to prepare the chosen model now. Held here rather than
  /// threaded through four constructors: this object already exists to carry
  /// what Settings reflects but does not own.
  var prepareTranslationModel: () -> Void = {}

  init(isDictating: Bool = false) {
    self.isDictating = isDictating
  }

  func setDownload(identifier: String, fraction: Double?) {
    if let fraction {
      languageDownloads[identifier] = fraction
    } else {
      languageDownloads[identifier] = nil
    }
  }
}
