import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var settings: AppSettings?
  private var statusItemController: StatusItemController?
  private var hudController: DictationHUDController?
  private var dictationController: DirectDictationController?
  private var readAloudController: ReadAloudController?
  private var settingsWindowController: SettingsWindowController?
  private var usageTracker: UsageTracker?
  private let settingsRuntimeState = SettingsRuntimeState()

  static func main() {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.run()
  }
 
 

  func applicationDidFinishLaunching(_ notification: Notification) {
    let settings = AppSettings()
    self.settings = settings
    let hudController = DictationHUDController(settings: settings)
    let usageTracker = UsageTracker()
    let dictationController = DirectDictationController(
      settings: settings,
      hudController: hudController,
      usageTracker: usageTracker
    )
    self.hudController = hudController
    self.dictationController = dictationController
    self.usageTracker = usageTracker

    let readAloudController = ReadAloudController(
      settings: settings,
      hudController: hudController
    )
    self.readAloudController = readAloudController

    let statusItemController = StatusItemController(
      toggleDictation: { dictationController.toggleFromMenu() },
      toggleReadAloud: { readAloudController.toggle() },
      openSettings: { [weak self] in self?.showSettings() }
    )
    self.statusItemController = statusItemController

    dictationController.onRecordingStateChange = {
      [weak statusItemController, weak settingsRuntimeState] isRecording in
      statusItemController?.setRecording(isRecording)
      settingsRuntimeState?.isDictating = isRecording
    }
    readAloudController.onSpeakingStateChange = {
      [weak statusItemController] isSpeaking in
      statusItemController?.setSpeaking(isSpeaking)
    }
    // Option+Escape toggles Read Aloud; the dictation controller owns
    // the event tap and fires this only while no session is active.
    dictationController.onReadAloudTriggered = { [weak readAloudController] in
      readAloudController?.toggle()
    }

    // Requests permissions and prepares the selected Speech Model
    // shortly after launch (CONTEXT.md).
    dictationController.start()

    applyKeyBindings()
    observeKeyBindings()
  }

  /// Rebinding in Settings updates the event tap and the status menu
  /// hints immediately; Observation re-arms after every change. The same
  /// loop pauses trigger handling while a key recorder is armed.
  private func observeKeyBindings() {
    guard let settings else { return }
    withObservationTracking {
      _ = settings.dictationTriggerBinding
      _ = settings.readAloudBinding
      _ = settings.isRecordingKeybind
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        self?.applyKeyBindings()
        self?.observeKeyBindings()
      }
    }
  }

  private func applyKeyBindings() {
    guard let settings else { return }
    dictationController?.applyKeyBindings()
    statusItemController?.setKeyBindings(
      trigger: settings.dictationTriggerBinding,
      readAloud: settings.readAloudBinding
    )
  }

  func applicationWillTerminate(_ notification: Notification) {
    dictationController?.stop()
  }

  private func showSettings() {
    guard let settings, let usageTracker else { return }
    if settingsWindowController == nil {
      settingsWindowController = SettingsWindowController(
        settings: settings,
        sounds: DictationHUDSounds(),
        runtimeState: settingsRuntimeState,
        usageTracker: usageTracker
      )
    }
    settingsWindowController?.show()
  }
}
