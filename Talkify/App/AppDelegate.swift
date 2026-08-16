import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var settings: AppSettings?
  private var statusItemController: StatusItemController?
  private var hudStage: HUDStage?
  private var hudController: DictationHUDController?
  private var dropTranscriptionController: DropTranscriptionController?
  private var dictationController: DirectDictationController?
  private var readAloudController: ReadAloudController?
  private var settingsWindowController: SettingsWindowController?
  private var usageTracker: UsageTracker?
  private let settingsRuntimeState = SettingsRuntimeState()
  private let updaterService = SparkleUpdaterService()

  static func main() {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.run()
  }
 
 

  func applicationDidFinishLaunching(_ notification: Notification) {
    let settings = AppSettings()
    self.settings = settings
    // One shape, two features. The stage owns the window and hands it out;
    // each feature's HUD controller only decides what its surface says.
    let stage = HUDStage(settings: settings)
    self.hudStage = stage
    let hudController = DictationHUDController(stage: stage, settings: settings)
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

    let dropTranscriptionController = DropTranscriptionController(
      settings: settings,
      hud: DropHUDController(stage: stage)
    )
    self.dropTranscriptionController = dropTranscriptionController
    dropTranscriptionController.start()
    dropTranscriptionController.onProgressChange = { [weak self, weak settings] fraction in
      self?.statusItemController?.setTranscriptionProgress(
        fraction,
        accent: settings?.sessionSettings.dropAccent ?? SettingsTheme.accentColor
      )
    }

    let statusItemController = StatusItemController(
      toggleDictation: { dictationController.toggleFromMenu() },
      toggleReadAloud: { readAloudController.toggle() },
      transcribeFile: { dropTranscriptionController.pickFile() },
      openSettings: { [weak self] in self?.showSettings() },
      checkForUpdates: { [weak self] in self?.updaterService.checkForUpdates() }
    )
    self.statusItemController = statusItemController

    dictationController.onRecordingStateChange = {
      [weak statusItemController, weak settingsRuntimeState] isRecording, session in
      let accent = session.flatMap {
        $0.voiceVisual == .glow ? $0.glowPalette.statusAccent : nil
      }
      statusItemController?.setRecording(isRecording, accent: accent)
      settingsRuntimeState?.isDictating = isRecording
    }
    dictationController.onLanguageDownloadChange = {
      [weak settingsRuntimeState] identifier, fraction in
      settingsRuntimeState?.setDownload(identifier: identifier, fraction: fraction)
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
    observeLanguages()

    // A background check is postponed while a session is running, so an update
    // window can never take focus mid-dictation and move the insertion target.
    updaterService.isBusy = { [weak settingsRuntimeState] in
      settingsRuntimeState?.isDictating ?? false
    }

    // Last: a scheduled check can show a window, and it must never land
    // before the status item and dictation are wired.
    updaterService.start()
  }

  /// Rebinding in Settings updates the event tap and the status menu
  /// hints immediately; Observation re-arms after every change. The same
  /// loop pauses trigger handling while a key recorder is armed.
  private func observeKeyBindings() {
    guard let settings else { return }
    withObservationTracking {
      _ = settings.dictationTriggerBinding
      _ = settings.secondaryTriggerBinding
      _ = settings.readAloudBinding
      _ = settings.isRecordingKeybind
      // The second trigger is only installed once a second language exists,
      // so the pick that enables it belongs in this loop too.
      _ = settings.secondaryRecognitionLocaleIdentifier
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        self?.applyKeyBindings()
        self?.observeKeyBindings()
      }
    }
  }

  /// Changing a language in Settings re-resolves and re-warms both, so the
  /// next keypress meets a prepared analyzer rather than a cold one.
  private func observeLanguages() {
    guard let settings else { return }
    withObservationTracking {
      _ = settings.recognitionLocaleIdentifier
      _ = settings.secondaryRecognitionLocaleIdentifier
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        self?.dictationController?.applyLanguages()
        self?.observeLanguages()
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
    // A transcript the HUD is still offering only exists in its staging folder,
    // so quitting writes it out rather than losing it.
    dropTranscriptionController?.commitOfferedTranscript()
  }

  private func showSettings() {
    guard let settings, let usageTracker else { return }
    if settingsWindowController == nil {
      settingsWindowController = SettingsWindowController(
        settings: settings,
        sounds: HUDSounds(),
        runtimeState: settingsRuntimeState,
        usageTracker: usageTracker,
        updater: updaterService
      )
    }
    settingsWindowController?.show()
  }
}
