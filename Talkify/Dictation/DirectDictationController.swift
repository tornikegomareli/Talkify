import AppKit

/// The impure half of Direct Dictation: owns the services, translates
/// trigger-monitor events into DictationSessionMachine actions, runs the
/// begin guards, and executes the machine's effects. Every state transition
/// lives in the machine; async completions come back to it as new actions.
@MainActor
final class DirectDictationController {
  /// Carries the session's captured settings while recording so the shell
  /// can mirror session-scoped looks (the status ghost's palette tint);
  /// nil when the session ends.
  var onRecordingStateChange: ((Bool, DictationSessionSettings?) -> Void)?
  /// Fired by the Read Aloud shortcut, only while no dictation session is
  /// active — speaking through the speaker path mid-dictation would feed
  /// the recognizer its own audio.
  var onReadAloudTriggered: (() -> Void)?
  /// A language model downloading, as a locale identifier and progress (0…1),
  /// or nil progress once it finishes. Settings shows it on the language row.
  var onLanguageDownloadChange: ((String, Double?) -> Void)?

  private static let noSpeechTimeout = Duration.seconds(15)

  private let settings: AppSettings
  private let dependencies: Dependencies

  private var keyEventMonitor: GlobalKeyEventMonitor?
  private var machine = DictationSessionMachine()
  private let ducking = AudioDuckingSession()
  /// Held for the length of a session. Without it, a Talkify that has sat
  /// idle for hours is napped, and the HUD's animation clock with it (#77).
  private let activity = ActivityAssertion(reason: "Direct Dictation session")
  private var focusedTarget: TextInsertionService.Target?
  private var noSpeechTask: Task<Void, Never>?
  private var permissionTask: Task<Void, Never>?
  private var permissionWatchTask: Task<Void, Never>?
  private var sessionStartTask: Task<Void, Never>?
  /// The finish in flight, carrying the session's last words to insertion.
  /// Tracked so teardown can wait for it instead of racing it.
  private var finishTask: Task<Void, Never>?
  private var isPrepared = false
  private var preparationFailureMessage: String?
  private var currentSessionSettings: DictationSessionSettings?
  /// The languages behind the two trigger keys, resolved to locales Apple
  /// Speech supports. `secondary` is nil unless a second language is chosen.
  private var primaryLocale: Locale?
  private var secondaryLocale: Locale?
  /// The pair a translate session would run, resolved with the languages.
  private var translationPair: TranslationPair?
  /// Whether that pair can translate right now. False while a model is still
  /// downloading, which refuses the translate key rather than letting someone
  /// speak into a rescue path.
  private var isTranslationReady = false
  /// Which slot's key began the session in flight, so the session runs in
  /// the language of the key that started it even if Settings change.
  private var activeSlot: GlobalKeyEventMonitor.TriggerSlot = .primary

  convenience init(
    settings: AppSettings,
    hudController: DictationHUDController,
    usageTracker: UsageTracker
  ) {
    self.init(
      settings: settings,
      dependencies: .live(hudController: hudController, usageTracker: usageTracker)
    )
  }

  init(settings: AppSettings, dependencies: Dependencies) {
    self.settings = settings
    self.dependencies = dependencies
    keyEventMonitor = GlobalKeyEventMonitor { [weak self] event in
      Task { @MainActor [weak self] in
        self?.handle(event)
      }
    }
  }

  func start() {
    applyKeyBindings()
    observeModelDownloads()
    requestPermissionsAndPrepare()
  }

  /// Routes model downloads to both places they matter: the Language section,
  /// and the HUD when a session is already waiting on that very language.
  private func observeModelDownloads() {
    let handler: @Sendable (SpeechRecognitionService.ModelDownload) -> Void = { [weak self] download in
      Task { @MainActor in
        self?.receive(download)
      }
    }

    Task { [dependencies] in
      await dependencies.setDownloadHandler(handler)
    }
  }

  private func receive(_ download: SpeechRecognitionService.ModelDownload) {
    onLanguageDownloadChange?(download.locale.identifier, download.fraction)

    // Only speak up in the HUD for the language this session is waiting on.
    guard machine.isSessionActive, locale(for: activeSlot) == download.locale else { return }

    guard let fraction = download.fraction else {
      dependencies.showModelDownload(nil)
      return
    }
    let name = SpeechLanguageCatalog.shortName(for: download.locale)
    dependencies.showModelDownload(
      "Downloading \(name)… \(Int(fraction * 100))%"
    )
  }

  /// Pushes the recorded Settings bindings into the event tap; called at
  /// start and whenever the Shortcuts section changes them.
  func applyKeyBindings() {
    keyEventMonitor?.setBindings(
      trigger: settings.dictationTriggerBinding,
      secondaryTrigger: settings.isSecondLanguageEnabled
        ? settings.secondaryTriggerBinding
        : nil,
      readAloud: settings.readAloudBinding,
      // Not installed until a target is chosen, so an unconfigured key
      // swallows nothing and behaves as if the feature were not there.
      translateTrigger: settings.isTranslationEnabled
        ? settings.translateTriggerBinding
        : nil
    )
    keyEventMonitor?.setEventHandlingSuspended(settings.isRecordingKeybind)
  }

  /// Re-resolves both languages and warms them. Called whenever the Language
  /// section changes a pick, so the key you press next is already prepared
  /// rather than building its analyzer on the keypress.
  func applyLanguages() {
    Task { [weak self] in
      guard let self else { return }
      do {
        try await prepareLanguages()
        isPrepared = true
        preparationFailureMessage = nil
      } catch {
        isPrepared = false
        preparationFailed(message: error.localizedDescription)
      }
    }
  }

  /// Resolves both picks, drops anything no longer bound to a key, then warms
  /// the primary language. The second warms behind it and never throws: a
  /// model that still needs downloading must not delay the primary key.
  private func prepareLanguages() async throws {
    let primary = try await dependencies.resolveLocale(
      settings.recognitionLocaleIdentifier
    )
    primaryLocale = primary

    // Resolved strictly: a stored pick this Mac cannot transcribe drops the
    // second language instead of quietly becoming the system default, which
    // would dictate in a language the user never chose.
    var secondary: Locale?
    if settings.isSecondLanguageEnabled {
      secondary = await dependencies.supportedLocale(
        settings.secondaryRecognitionLocaleIdentifier
      )
    }
    // A second language equal to the first is not a second language.
    secondaryLocale = secondary == primary ? nil : secondary

    let bound = [primary, secondaryLocale].compactMap(\.self)
    await dependencies.retainOnly(bound)
    try await dependencies.prewarm(primary)

    if let secondaryLocale {
      try? await dependencies.prewarm(secondaryLocale)
    }

    // Translation last, and never fatal. A model that still needs downloading
    // must not leave isPrepared false, which would refuse plain dictation for
    // a feature the user may never press.
    let pair = settings.translationPair(from: primary)
    translationPair = pair
    await dependencies.retainTranslation(pair)
    if let pair {
      isTranslationReady = await dependencies.prewarmTranslation(pair)
    } else {
      isTranslationReady = false
    }
  }

  private func locale(for slot: GlobalKeyEventMonitor.TriggerSlot) -> Locale? {
    switch slot {
    case .primary: primaryLocale
    case .secondary: secondaryLocale ?? primaryLocale
    // The source of a translation is always the primary language. The second
    // language exists so a different language can be dictated; translating
    // from it would put two settings behind one key.
    case .translate: primaryLocale
    }
  }

  /// The HUD's language tag, shown only once a second language exists: with
  /// one language there is nothing to disambiguate.
  private var activeLanguageTag: String? {
    guard secondaryLocale != nil, let locale = locale(for: activeSlot) else { return nil }
    return SpeechLanguageCatalog.tag(for: locale)
  }

  /// True while a released trigger is still being turned into inserted text.
  /// Termination waits on this rather than racing it.
  var isFinishing: Bool { finishTask != nil }

  /// Waits for an in-flight finish to insert its text, giving up after
  /// `timeout` so a stuck insertion cannot hold the quit forever. Giving up
  /// only stops the waiting; the finish keeps running until the process goes.
  func waitForFinish(timeout: Duration) async {
    guard let finishTask else { return }
    await awaitValue(of: finishTask, orGiveUpAfter: timeout)
  }

  func stop() {
    // Before anything else: quitting mid-session must not leave the Mac quiet.
    ducking.restore()
    noSpeechTask?.cancel()
    permissionTask?.cancel()
    permissionWatchTask?.cancel()
    sessionStartTask?.cancel()
    // The finish is deliberately not cancelled: it holds the user's last
    // words, and termination has already given it its window through
    // waitForFinish.
    keyEventMonitor?.stop()
    isPrepared = false

    // A finish still in flight holds the user's last words. Shutting the
    // speech service down beside it would cancel the very session the finish
    // is reading, and whichever task the scheduler ran first would decide
    // whether that text was inserted or dropped. Waiting first makes the
    // order a rule instead of a race.
    //
    // Bounded, because stop() is not only called on the way out: a wedged
    // insertion must not keep the speech service alive forever.
    Task { [dependencies, finishTask] in
      if let finishTask {
        await awaitValue(of: finishTask, orGiveUpAfter: .seconds(2))
      }
      await dependencies.shutDownRecognition()
      await dependencies.shutDownTranslation()
    }
  }

  func toggleFromMenu() {
    // The menu item has no language of its own, so it dictates in the first.
    if !machine.isSessionActive {
      activeSlot = .primary
    }
    send(.menuToggled(now: .now))
  }

  func requestPermissionsAndPrepare() {
    permissionTask?.cancel()
    isPrepared = false
    preparationFailureMessage = nil

    permissionTask = Task { [weak self] in
      guard let self else { return }

      let microphoneGranted = await dependencies.requestMicrophoneAccess()
      guard !Task.isCancelled else { return }
      guard microphoneGranted else {
        preparationFailed(message: "Microphone permission required")
        return
      }

      let speechGranted = await dependencies.requestSpeechAccess()
      guard !Task.isCancelled else { return }
      guard speechGranted else {
        preparationFailed(message: "Speech permission required")
        return
      }

      // Ask for one privacy permission at a time. Requesting Accessibility
      // beside the microphone prompt makes macOS stack or suppress dialogs.
      dependencies.requestAccessibilityAccess()

      do {
        try await prepareLanguages()
      } catch {
        guard !Task.isCancelled else { return }
        preparationFailed(message: error.localizedDescription)
        return
      }

      isPrepared = true
      installTriggerMonitor()
    }
  }

  /// Watches for a permission the user is granting right now.
  ///
  /// Accessibility is granted in System Settings while Talkify is already
  /// running, and macOS tells the app nothing when it changes. Checking once at
  /// launch meant the trigger key stayed dead after the user had done everything
  /// right, with no hint that a relaunch was needed. This polls instead, and
  /// installs the tap the moment it is allowed to.
  private func startPermissionWatch() {
    guard permissionWatchTask == nil else { return }

    permissionWatchTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(1))
        guard !Task.isCancelled, let self else { return }
        // Never interrupt the dialog the user is reading.
        guard !dependencies.isPermissionAlertPresenting() else { continue }
        guard dependencies.hasAccessibilityAccess() else { continue }

        permissionWatchTask = nil
        if keyEventMonitor?.start() == true {
          dependencies.showMessage("Talkify is ready", nil)
        } else {
          dependencies.showRelaunchAlert()
        }
        return
      }
    }
  }

  /// The machine's current state, so tests can pin transitions the
  /// controller's effects produce.
  var sessionStateForTesting: DictationSessionMachine.State { machine.state }
  /// Whether preparation has finished, so a test can wait for the state it
  /// needs rather than for a duration. Preparation grew a translation tail,
  /// and a fixed sleep long enough on an idle machine is not long enough on a
  /// loaded one.
  var isPreparedForTesting: Bool { isPrepared }
  var isTranslationReadyForTesting: Bool { isTranslationReady }

  func handle(_ event: GlobalKeyEventMonitor.Event) {
    switch event {
    case let .triggerPressed(slot):
      // While a session runs, only the key that started it controls it. The
      // other language's key is inert until this session ends, so a latched
      // German session cannot be stopped by the English key.
      if machine.isSessionActive {
        guard slot == activeSlot else { return }
      } else {
        activeSlot = slot
      }
      send(.triggerPressed(now: .now))
    case let .triggerReleased(slot):
      guard slot == activeSlot else { return }
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
        await dependencies.cancelRecognition()
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
      let session = DictationSessionSettings(
        settings: settings,
        translation: activeSlot == .translate ? translationPair : nil
      )
      currentSessionSettings = session
      dependencies.showListening(
        focusedTarget?.displayID,
        latched,
        session,
        activeLanguageTag
      )
    case .showLatched:
      dependencies.showLatched()
    case .showLiveText:
      if let pendingLiveText {
        dependencies.showLiveText(pendingLiveText)
      }
    case .showFinalizing:
      dependencies.showFinalizing()
    case .hideHUD:
      dependencies.hideHUD()
    case let .notifyRecording(isRecording):
      // Ducking rides this effect because it is the one signal that fires on
      // every terminal path — inserted, cancelled, failed, or timed out — so
      // the volume cannot be left down by a route nobody thought about.
      if isRecording {
        if currentSessionSettings?.ducksOtherAudio == true { ducking.duck() }
      } else {
        ducking.restore()
        activity.release()
        focusedTarget = nil
        sessionStartTask = nil
        currentSessionSettings = nil
      }
      onRecordingStateChange?(isRecording, currentSessionSettings)
    case .triggerReadAloud:
      onReadAloudTriggered?()
    }
  }

  /// The text carried alongside the current `updateReceived` action; the
  /// machine decides whether it shows, the controller remembers what.
  private var pendingLiveText: String?

  private func checkAndBegin() {
    // Held here rather than once recording starts: the first HUD frames are
    // what a napped process draws badly, and by then they have been drawn.
    // Every rejection below releases it, because .beginRejected produces no
    // effects and nothing downstream would.
    activity.hold()

    guard isPrepared else {
      dependencies.showMessage(preparationFailureMessage ?? "Preparing speech…", nil)
      activity.release()
      send(.beginRejected)
      return
    }

    if !dependencies.hasAccessibilityAccess() {
      // One dialog that explains it, not the system prompt again on every press.
      dependencies.showAccessibilitySetupAlert()
      startPermissionWatch()
      activity.release()
      send(.beginRejected)
      return
    }

    let target = dependencies.captureFocusedTarget()
    if target?.isSecure == true {
      dependencies.showMessage("Secure field", target?.displayID)
      activity.release()
      send(.beginRejected)
      return
    }

    // Refused before the user speaks, which is much better than letting them
    // finish a sentence into a rescue path.
    if activeSlot == .translate, !isTranslationReady {
      dependencies.showMessage(
        translationPair == nil ? "No translation language" : "Translation not ready",
        target?.displayID
      )
      retryTranslationPrewarm()
      activity.release()
      send(.beginRejected)
      return
    }

    focusedTarget = target
    send(.beginApproved)
  }

  /// Tries the pair again after a refusal, so a key pressed once while the
  /// model was still downloading does not stay dead until Settings is touched.
  private func retryTranslationPrewarm() {
    guard let pair = translationPair, !isTranslationReady else { return }
    Task { [weak self] in
      let ready = await self?.dependencies.prewarmTranslation(pair) ?? false
      guard let self, translationPair == pair else { return }
      isTranslationReady = ready
    }
  }

  private func beginRecognition() {
    guard let locale = locale(for: activeSlot) else {
      fail(message: "Preparing speech…", wasCancelled: false)
      return
    }

    sessionStartTask = Task { [weak self] in
      guard let self else { return }
      do {
        try await dependencies.startRecognition(
          locale,
          { [weak self] update in
            Task { @MainActor [weak self] in
              self?.receive(update)
            }
          },
          { [weak self] message in
            Task { @MainActor [weak self] in
              self?.fail(message: message, wasCancelled: false)
            }
          },
          { [weak self] level in
            Task { @MainActor [weak self] in
              self?.dependencies.showAudioLevel(level)
            }
          }
        )
        guard !Task.isCancelled else {
          await dependencies.cancelRecognition()
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

  /// Writes the session's entry, after any translation and before the
  /// insertion: an entry names where the words were headed, and words the
  /// paste then loses are exactly the words history exists to keep.
  private func recordHistory(
    spoken: String,
    delivered: String?,
    session: DictationSessionSettings
  ) async {
    guard session.historyEnabled, !spoken.isEmpty else { return }
    await dependencies.recordHistory(
      delivered ?? spoken,
      historySource(for: session.insertionDestination),
      session.historyFolder
    )
  }

  /// What the history entry names as this session's destination.
  ///
  /// Clipboard-only never aims at an application, so naming the one that
  /// happened to hold focus would be a lie. Everything else names where the
  /// words were headed when they were spoken.
  private func historySource(for destination: InsertionDestination) -> String? {
    guard destination != .clipboardOnly else { return "Clipboard" }
    return focusedTarget?.applicationName
  }

  /// Finishes recognition and routes the insertion outcome to its terminal UI.
  ///
  /// - Parameter speakingDuration: The completed session's measured speech time.
  private func finishRecognition(speakingDuration: TimeInterval) {
    finishTask = Task { [weak self] in
      guard let self else { return }
      defer { finishTask = nil }
      do {
        let spoken = try await dependencies.finishRecognition()
        dependencies.hideHUD()
        // Delivery follows the session snapshot, so a Settings change
        // mid-session applies to the next session (ADR-0004).
        let session = currentSessionSettings ?? settings.sessionSettings

        // The one place between recognition and insertion where the words may
        // change. A transform that fails delivers nothing: the trigger
        // promised a translation, and pasting the untranslated words instead
        // lands the wrong language in someone else's document.
        var text = spoken
        if let pair = session.translation, !spoken.isEmpty {
          do {
            text = try await dependencies.translateText(spoken, pair)
          } catch {
            await recordHistory(spoken: spoken, delivered: nil, session: session)
            // Clipboard-only whatever the session's destination: nothing is
            // pasted, and the words survive where the user can reach them.
            _ = await dependencies.insertText(spoken, nil, .clipboardOnly)
            // Ended, not failed: a failure action would drive the machine to
            // cancelling and cancel a session that has already finished.
            send(.sessionEnded)
            dependencies.showMessage("Couldn't translate", nil)
            return
          }
        }

        await recordHistory(spoken: spoken, delivered: text, session: session)
        let outcome = await dependencies.insertText(
          text, focusedTarget, session.insertionDestination
        )
        switch outcome {
        case .inserted, .copiedToClipboard:
          dependencies.playPasteSound()
          send(.sessionEnded)
          let wordCount = UsageMetrics.wordCount(in: text)
          await dependencies.recordSession(wordCount, speakingDuration)
        case .unavailable:
          send(.sessionEnded)
          dependencies.showMessage("Couldn't insert text", nil)
        }
      } catch {
        fail(message: error.localizedDescription, wasCancelled: false)
      }
      finishTask = nil
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
        await dependencies.cancelRecognition()
        send(.sessionEnded)
        dependencies.showMessage(message, nil)
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
    guard dependencies.hasAccessibilityAccess() else {
      dependencies.requestAccessibilityAccess()
      startPermissionWatch()
      return
    }

    // Granted, but macOS decides what this process may do when it launches, so
    // the tap can still be refused. Only a fresh launch clears that, and saying
    // so is the whole point of the dialog.
    guard keyEventMonitor?.start() == true else {
      dependencies.showRelaunchAlert()
      return
    }
  }

  private func preparationFailed(message: String) {
    preparationFailureMessage = message
    dependencies.showMessage(message, nil)
  }
}
