import AppKit

/// The impure half of Direct Dictation: owns the services, translates
/// trigger-monitor events into DictationSessionMachine actions, runs the
/// begin guards, and executes the machine's effects. Every state transition
/// lives in the machine; async completions come back to it as new actions.
@MainActor
final class DirectDictationController {
  var onRecordingStateChange: ((Bool) -> Void)?
  /// Fired by the Read Aloud shortcut, only while no dictation session is
  /// active — speaking through the speaker path mid-dictation would feed
  /// the recognizer its own audio.
  var onReadAloudTriggered: (() -> Void)?

  private static let noSpeechTimeout = Duration.seconds(15)

  private let settings: AppSettings
  private let speechService = SpeechRecognitionService()
  private let hudController: DictationHUDController
  private let textInsertionService = TextInsertionService()
  private let usageTracker: UsageTracker

  private var keyEventMonitor: GlobalKeyEventMonitor?
  private var machine = DictationSessionMachine()
  private var focusedTarget: TextInsertionService.Target?
  private var noSpeechTask: Task<Void, Never>?
  private var permissionTask: Task<Void, Never>?
  private var sessionStartTask: Task<Void, Never>?
  private var isPrepared = false
  private var preparationFailureMessage: String?

  init(
    settings: AppSettings,
    hudController: DictationHUDController,
    usageTracker: UsageTracker
  ) {
    self.settings = settings
    self.hudController = hudController
    self.usageTracker = usageTracker
    keyEventMonitor = GlobalKeyEventMonitor { [weak self] event in
      Task { @MainActor [weak self] in
        self?.handle(event)
      }
    }
  }

  func start() {
    applyKeyBindings()
    requestPermissionsAndPrepare()
  }

  /// Pushes the recorded Settings bindings into the event tap; called at
  /// start and whenever the Shortcuts section changes them.
  func applyKeyBindings() {
    keyEventMonitor?.setBindings(
      trigger: settings.dictationTriggerBinding,
      readAloud: settings.readAloudBinding
    )
    keyEventMonitor?.setEventHandlingSuspended(settings.isRecordingKeybind)
  }

  func stop() {
    noSpeechTask?.cancel()
    permissionTask?.cancel()
    sessionStartTask?.cancel()
    keyEventMonitor?.stop()
    isPrepared = false

    Task {
      await speechService.shutDown()
    }
  }

  func toggleFromMenu() {
    send(.menuToggled(now: .now))
  }

  func requestPermissionsAndPrepare() {
    permissionTask?.cancel()
    isPrepared = false
    preparationFailureMessage = nil
    PermissionService.requestAccessibilityAccess()
    PermissionService.requestInputMonitoringAccess()

    permissionTask = Task { [weak self] in
      guard let self else { return }

      let microphoneGranted = await PermissionService.requestMicrophoneAccess()
      guard !Task.isCancelled else { return }
      guard microphoneGranted else {
        preparationFailed(message: "Microphone permission required")
        return
      }

      let speechGranted = await PermissionService.requestSpeechAccess()
      guard !Task.isCancelled else { return }
      guard speechGranted else {
        preparationFailed(message: "Speech permission required")
        return
      }

      do {
        _ = try await speechService.prewarmPreferredLocale()
      } catch {
        guard !Task.isCancelled else { return }
        preparationFailed(message: error.localizedDescription)
        return
      }

      isPrepared = true
      guard PermissionService.hasAccessibilityAccess else {
        hudController.showMessage("Accessibility permission required")
        return
      }

      guard PermissionService.hasInputMonitoringAccess else {
        hudController.showMessage("Input Monitoring permission required")
        return
      }

      installTriggerMonitor()
    }
  }

  private func handle(_ event: GlobalKeyEventMonitor.Event) {
    switch event {
    case .triggerPressed:
      send(.triggerPressed(now: .now))
    case .triggerReleased:
      send(.triggerReleased(now: .now))
    case .cancelPressed:
      send(.escapePressed)
    case .readAloudPressed:
      send(.readAloudPressed)
    }
  }

  private func send(_ action: DictationSessionMachine.Action) {
    perform(machine.reduce(action))
  }

  private func perform(_ effects: [DictationSessionMachine.Effect]) {
    for effect in effects {
      perform(effect)
    }
  }

  private func perform(_ effect: DictationSessionMachine.Effect) {
    switch effect {
    case .checkAndBegin:
      checkAndBegin()
    case .beginRecognition:
      beginRecognition()
    case let .finishRecognition(speakingDuration):
      finishRecognition(speakingDuration: speakingDuration)
    case .cancelRecognition:
      Task { [weak self] in
        guard let self else { return }
        await speechService.cancel()
        send(.sessionEnded)
      }
    case .cancelStartTask:
      sessionStartTask?.cancel()
    case let .setEscapeCapture(enabled):
      keyEventMonitor?.setEscapeCaptureEnabled(enabled)
    case .startNoSpeechTimer:
      startNoSpeechTimer()
    case .stopNoSpeechTimer:
      stopNoSpeechTimer()
    case let .showListening(latched):
      hudController.showListening(
        on: focusedTarget?.displayID,
        isLatched: latched,
        settings: settings.sessionSettings
      )
    case .showLatched:
      hudController.showLatched()
    case .showLiveText:
      if let pendingLiveText {
        hudController.showLiveText(pendingLiveText)
      }
    case .showFinalizing:
      hudController.showFinalizing()
    case .hideHUD:
      hudController.hide()
    case let .notifyRecording(isRecording):
      if !isRecording {
        focusedTarget = nil
        sessionStartTask = nil
      }
      onRecordingStateChange?(isRecording)
    case .triggerReadAloud:
      onReadAloudTriggered?()
    }
  }

  /// The text carried alongside the current `updateReceived` action; the
  /// machine decides whether it shows, the controller remembers what.
  private var pendingLiveText: String?

  private func checkAndBegin() {
    guard isPrepared else {
      hudController.showMessage(preparationFailureMessage ?? "Preparing speech…")
      send(.beginRejected)
      return
    }

    if !PermissionService.hasAccessibilityAccess {
      PermissionService.requestAccessibilityAccess()
      hudController.showMessage("Accessibility permission required")
      send(.beginRejected)
      return
    }

    let target = textInsertionService.captureFocusedTarget()
    if target?.isSecure == true {
      hudController.showMessage("Secure field", on: target?.displayID)
      send(.beginRejected)
      return
    }

    focusedTarget = target
    send(.beginApproved)
  }

  private func beginRecognition() {
    sessionStartTask = Task { [weak self] in
      guard let self else { return }
      do {
        try await speechService.start(
          updateHandler: { [weak self] update in
            Task { @MainActor [weak self] in
              self?.receive(update)
            }
          },
          failureHandler: { [weak self] message in
            Task { @MainActor [weak self] in
              self?.fail(message: message, wasCancelled: false)
            }
          },
          levelHandler: { [weak self] level in
            Task { @MainActor [weak self] in
              self?.hudController.showAudioLevel(level)
            }
          }
        )
        guard !Task.isCancelled else {
          await speechService.cancel()
          send(.sessionEnded)
          return
        }
        sessionStartTask = nil
        send(.recognitionStarted(now: .now))
      } catch {
        sessionStartTask = nil
        if Task.isCancelled {
          send(.recognitionFailed(wasCancelled: true))
        } else {
          fail(message: error.localizedDescription, wasCancelled: false)
        }
      }
    }
  }

  private func receive(_ update: SpeechRecognitionService.Update) {
    let displayText = update.displayText
    let hasVisibleText = !displayText
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .isEmpty
    pendingLiveText = displayText
    send(.updateReceived(hasVisibleText: hasVisibleText))
    pendingLiveText = nil
  }

  private func finishRecognition(speakingDuration: TimeInterval) {
    Task { [weak self] in
      guard let self else { return }
      do {
        let text = try await speechService.finish()
        hudController.hide()
        await textInsertionService.insert(text, into: focusedTarget)
        hudController.playPasteSound()
        send(.sessionEnded)
        let wordCount = UsageMetrics.wordCount(in: text)
        await usageTracker.recordSession(
          wordCount: wordCount,
          speakingDuration: speakingDuration
        )
      } catch {
        fail(message: error.localizedDescription, wasCancelled: false)
      }
    }
  }

  /// A failure path always ends with the message shown after the reset —
  /// the machine handles the transition, the controller the message.
  private func fail(message: String, wasCancelled: Bool) {
    let effects = machine.reduce(.recognitionFailed(wasCancelled: wasCancelled))
    guard !effects.isEmpty else { return }

    if effects.contains(.cancelRecognition) {
      // Active failure: cancel recognition, reset, then show why.
      for effect in effects where effect != .cancelRecognition {
        perform(effect)
      }
      Task { [weak self] in
        guard let self else { return }
        await speechService.cancel()
        send(.sessionEnded)
        hudController.showMessage(message)
      }
    } else {
      perform(effects)
    }
  }

  private func startNoSpeechTimer() {
    noSpeechTask?.cancel()
    noSpeechTask = Task { [weak self] in
      try? await Task.sleep(for: Self.noSpeechTimeout)
      guard !Task.isCancelled else { return }
      self?.send(.noSpeechTimedOut)
    }
  }

  private func stopNoSpeechTimer() {
    noSpeechTask?.cancel()
    noSpeechTask = nil
  }

  private func installTriggerMonitor() {
    let installed = keyEventMonitor?.start() == true
    guard installed else {
      hudController.showMessage("Accessibility permission required")
      return
    }
  }

  private func preparationFailed(message: String) {
    preparationFailureMessage = message
    hudController.showMessage(message)
  }
}
