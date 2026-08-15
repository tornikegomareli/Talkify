import AppKit

/// The setup conversation Talkify has to have with the user.
///
/// Accessibility and Input Monitoring are granted in System Settings, and macOS
/// hands the running process a stale answer afterwards: the event tap keeps
/// being refused until the app is launched again. A transient HUD message is the
/// wrong place to say that, because it disappears while the user is still in
/// System Settings. This is a real dialog that waits, names the pane to open,
/// and can relaunch Talkify itself.
@MainActor
enum PermissionAlert {
  enum Permission {
    case accessibility
    case inputMonitoring

    var title: String {
      switch self {
      case .accessibility: "Accessibility"
      case .inputMonitoring: "Input Monitoring"
      }
    }

    var reason: String {
      switch self {
      case .accessibility:
        "so Talkify can put your words into the app you were typing in"
      case .inputMonitoring:
        "so Talkify can tell when you hold the dictation key"
      }
    }

    var settingsURL: String {
      switch self {
      case .accessibility:
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
      case .inputMonitoring:
        "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
      }
    }
  }

  /// True while a dialog is on screen, so a second trigger press cannot stack
  /// another one behind it.
  private(set) static var isPresenting = false

  /// Asks for a permission that has not been granted yet.
  static func requestSetup(for permission: Permission) {
    guard !isPresenting else { return }

    let alert = NSAlert()
    alert.alertStyle = .informational
    alert.messageText = "Talkify needs \(permission.title)"
    alert.informativeText = """
      Turn Talkify on in System Settings → Privacy & Security → \
      \(permission.title), \(permission.reason).

      macOS only applies this when Talkify starts, so reopen it once you have \
      granted the permission.
      """
    alert.addButton(withTitle: "Open Settings")
    alert.addButton(withTitle: "Quit and Reopen")
    alert.addButton(withTitle: "Later")

    switch run(alert) {
    case .alertFirstButtonReturn:
      open(permission)
    case .alertSecondButtonReturn:
      relaunch()
    default:
      break
    }
  }

  /// Shown once the permission reads as granted but the key still cannot be
  /// watched, which only a fresh launch clears.
  static func requestRelaunch() {
    guard !isPresenting else { return }

    let alert = NSAlert()
    alert.alertStyle = .informational
    alert.messageText = "Reopen Talkify to finish"
    alert.informativeText = """
      The permission is granted. macOS applies it to Talkify only when the app \
      starts, so the dictation key stays inactive until you reopen it.
      """
    alert.addButton(withTitle: "Quit and Reopen")
    alert.addButton(withTitle: "Later")

    if run(alert) == .alertFirstButtonReturn {
      relaunch()
    }
  }

  static func open(_ permission: Permission) {
    guard let url = URL(string: permission.settingsURL) else { return }
    NSWorkspace.shared.open(url)
  }

  /// Quits and comes back. `createsNewApplicationInstance` is required: without
  /// it macOS activates the copy that is still running instead of starting the
  /// replacement, and terminating only after the new instance is on its way
  /// keeps a gap from swallowing the relaunch.
  static func relaunch() {
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.createsNewApplicationInstance = true

    NSWorkspace.shared.openApplication(
      at: Bundle.main.bundleURL,
      configuration: configuration
    ) { _, _ in
      Task { @MainActor in
        NSApp.terminate(nil)
      }
    }
  }

  /// Talkify has no Dock icon, and an accessory app's alert opens behind
  /// whatever the user is looking at. The policy switches for as long as the
  /// dialog is up, the same trade the updater makes for its window.
  private static func run(_ alert: NSAlert) -> NSApplication.ModalResponse {
    isPresenting = true
    defer { isPresenting = false }

    let policy = NSApp.activationPolicy()
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    defer { NSApp.setActivationPolicy(policy) }

    return alert.runModal()
  }
}
