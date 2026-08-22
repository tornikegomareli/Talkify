import Foundation
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

  /// The language the targets above are measured from, which Settings needs
  /// in hand to name a pair. Installing a model is something only Settings can
  /// do, because only Settings has a window.
  var translationSource: Locale.Language?

  /// Waits for a model to install and loads it, answering how that ended.
  /// Held here rather than threaded through four constructors: this object
  /// already exists to carry what Settings reflects but does not own.
  var installTranslationModel: (TranslationPair) async -> TranslationCoordinator.InstallOutcome
    = { _ in .unavailable }

  /// The pair being installed, or nil when nothing is. Held here because the
  /// view that starts an install is replaced whenever the user changes Settings
  /// section, and the modifier that drives Apple's download has to outlive that.
  var installingTranslationPair: TranslationPair?

  /// The language whose model never arrived, until it is dismissed or another
  /// is chosen. Held here rather than in the Language view: leaving that
  /// section replaces the view, and a revert nobody explained is worse than
  /// the failure itself.
  var translationInstallFailure: String?

  /// Abandons a wait for a model. Reachable whether or not the view that
  /// started it still exists.
  var stopInstallingTranslationModel: () -> Void = {}

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
