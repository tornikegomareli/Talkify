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
  private let launchAtLoginService = LaunchAtLoginService()

  static func main() {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.run()
  }
 
 

  /// True while this process hosts the test suite rather than a user.
  ///
  /// The live launch path requests microphone and speech permissions and
  /// installs the event tap, which pops system permission dialogs over every
  /// automated test run on a machine that has not granted them. Hosting
  /// tests skips the launch entirely: tests build the objects they exercise,
  /// and a test that means to see a permission prompt drives
  /// PermissionService itself, on purpose.
  private static var isHostingTests: Bool {
    let environment = ProcessInfo.processInfo.environment
    return environment["XCTestSessionIdentifier"] != nil
      || environment["XCTestConfigurationFilePath"] != nil
      || environment["XCTestBundlePath"] != nil
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    guard !Self.isHostingTests else { return }

    // Before anything can be staged: a crash or a force-quit while a
    // transcript card was on screen leaves the user's speech in cleartext
    // under $TMPDIR, and nothing else ever removes it.
    StagedTranscript.sweep()

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
    // Settings drives translation directly. Routing it through the dictation
    // controller would only make that controller forward three things it has
    // no opinion about.
    let translation = dictationController.translation
    settingsRuntimeState.installTranslationModel = { [weak translation] pair in
      await translation?.install(pair) ?? .unavailable
    }
    settingsRuntimeState.stopInstallingTranslationModel = { [weak translation] in
      translation?.stopInstalling()
    }
    translation.onTargetsChange = { [weak settingsRuntimeState] targets, source in
      settingsRuntimeState?.translationTargets = targets
      settingsRuntimeState?.translationSource = source
    }
    translation.onStateChange = { [weak settingsRuntimeState] state in
      settingsRuntimeState?.translationModelState = state
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

    // Compiles the HUD's shaders now, so the cost does not land on the first
    // frames of the first dictation.
    HUDShaderWarmUp.start()

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
      _ = settings.translateTriggerBinding
      _ = settings.isRecordingKeybind
      // The second trigger is only installed once a second language exists,
      // so the pick that enables it belongs in this loop too.
      _ = settings.secondaryRecognitionLocaleIdentifier
      // The target is what installs the translate trigger, the same reason the
      // second language's pick belongs in this loop.
      _ = settings.translationTargetIdentifier
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
      // The translation target belongs here as well as in the key-binding
      // loop: that one installs the trigger, this one resolves and warms the
      // pair the trigger will use. Without it a changed target reinstalled a
      // trigger that had nothing to translate into.
      _ = settings.translationTargetIdentifier
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

  /// A released trigger whose text has not landed yet is the one thing worth
  /// delaying a quit for: the user spoke it and expects to see it. AppKit's
  /// deferred termination is the only way to wait, because
  /// `applicationWillTerminate` is synchronous and the finish needs the main
  /// actor to make progress.
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard let dictationController, dictationController.isFinishing else {
      return .terminateNow
    }
    Task { @MainActor in
      await dictationController.waitForFinish()
      sender.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
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
        updater: updaterService,
        launchAtLogin: launchAtLoginService
      )
    }
    settingsWindowController?.show()
  }
}
