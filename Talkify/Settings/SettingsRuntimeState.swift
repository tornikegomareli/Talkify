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
