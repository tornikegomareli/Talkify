import Observation

/// Live app state the Settings surface reflects but does not own: whether a
/// Direct Dictation session is active (drives the changes-apply-next-session
/// notice). The composition root updates it from the dictation controller.
@MainActor
@Observable
final class SettingsRuntimeState {
  var isDictating: Bool

  init(isDictating: Bool = false) {
    self.isDictating = isDictating
  }
}
