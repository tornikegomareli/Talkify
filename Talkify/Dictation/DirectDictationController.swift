import AppKit
import SwiftUI

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
  /// The HUD surface the editable-draft variant drives directly (draft
  /// text, selection, and the review field); nil on the dependency-seam
  /// init, which no production path uses for a draft session.
  private let hudController: DictationHUDController?
  /// The MyVoice transcript capture boundary. Its saves are detached and
  /// never block or fail dictation; off by default behind
  /// `myvoiceCaptureEnabled`.
  private let myVoiceService: MyVoiceCaptureServicing

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
  /// Which slot's key began the session in flight, so the session runs in
  /// the language of the key that started it even if Settings change.
  private var activeSlot: GlobalKeyEventMonitor.TriggerSlot = .primary

  convenience init(
    settings: AppSettings,
    hudController: DictationHUDController,
    usageTracker: UsageTracker,
    myVoiceService: MyVoiceCaptureServicing? = nil
  ) {
    self.init(
      settings: settings,
      dependencies: .live(hudController: hudController, usageTracker: usageTracker),
      hudController: hudController,
      myVoiceService: myVoiceService
    )
  }

  init(
    settings: AppSettings,
    dependencies: Dependencies,
    hudController: DictationHUDController? = nil,
    myVoiceService: MyVoiceCaptureServicing? = nil
  ) {
    self.settings = settings
    self.dependencies = dependencies
    self.hudController = hudController
    self.myVoiceService = myVoiceService ?? MyVoiceCaptureService(enabled: { true })
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
      readAloud: settings.readAloudBinding
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
  }

  private func locale(for slot: GlobalKeyEventMonitor.TriggerSlot) -> Locale? {
    switch slot {
    case .primary: primaryLocale
    case .secondary: secondaryLocale ?? primaryLocale
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
    case .returnPressed:
      send(.returnPressed)
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
    case let .setReturnCapture(enabled):
      keyEventMonitor?.setReturnCaptureEnabled(enabled)
    case .startNoSpeechTimer:
      startNoSpeechTimer()
    case .stopNoSpeechTimer:
      stopNoSpeechTimer()
    case let .showListening(latched):
      let session = settings.sessionSettings
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
      if let pendingLiveText, let pendingReplacement {
        // A replacement round keeps its held draft on screen with the
        // streaming words spliced over the selection, and highlights
        // exactly the range the round will commit; a fresh round shows
        // the words alone (DraftReplacement).
        hudController?.showLiveText(
          DraftReplacement.liveBandText(replacement: pendingReplacement, liveText: pendingLiveText),
          replacementHighlight: pendingReplacement.highlightRange(liveText: pendingLiveText)
        )
      } else if let pendingLiveText {
        dependencies.showLiveText(pendingLiveText)
      }
    case .showFinalizing:
      dependencies.showFinalizing()
    case .showEditableDraft:
      showEditableDraft()
    case .pasteDraft:
      pasteDraft()
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
        sessionSpeakingDuration = 0
        pendingReplacement = nil
        pendingRawTranscript = nil
        myVoiceSessionStartedAt = nil
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

    // A replacement round targets the HUD's own selection: the session's
    // outer target stays captured, and the round's words splice into the
    // held draft when they arrive. Nothing here can reject a round — the
    // recognizer the session already runs on is warm by definition.
    if machine.isReviewing {
      pendingReplacement = captureDraftSelection()
      // The selection the round will overwrite is marked from the start,
      // before any words arrive, so the highlight is on screen the moment
      // the round begins listening.
      if let pendingReplacement {
        hudController?.markReplacementSelection(pendingReplacement.range)
      }
      send(.beginApproved)
      return
    }

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

    focusedTarget = target
    send(.beginApproved)
  }

  private func beginRecognition() {
    guard let locale = locale(for: activeSlot) else {
      fail(message: "Preparing speech…", wasCancelled: false)
      return
    }

    myVoiceSessionStartedAt = Date()

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
  /// The default path inserts as before. The editable-draft variant holds
  /// the text in the HUD instead: the machine moves to `.reviewing`, where
  /// Return pastes, the trigger starts a replacement round, and Escape
  /// discards. A replacement round's text is spliced into the held draft at
  /// the selection the round began with, and every round's speech time
  /// joins the session's total for Insights.
  ///
  /// - Parameter speakingDuration: The completed round's measured speech time.
  private func finishRecognition(speakingDuration: TimeInterval) {
    finishTask = Task { [weak self] in
      guard let self else { return }
      defer { finishTask = nil }
      let startedAt = myVoiceSessionStartedAt ?? Date()
      do {
        let text = try await dependencies.finishRecognition()
        let stoppedAt = Date()
        sessionSpeakingDuration += speakingDuration
        if let pending = pendingReplacement {
          commitReplacement(text, into: pending)
        } else if currentSessionSettings?.draftStyle == .editableDraft {
          if text.isEmpty {
            dependencies.hideHUD()
            send(.sessionEnded)
            myVoiceSessionStartedAt = nil
            pendingRawTranscript = nil
          } else {
            if pendingRawTranscript == nil { pendingRawTranscript = text }
            hudController?.setDraft(text)
            send(.finishCompleted)
          }
        } else {
          dependencies.hideHUD()
          // Delivery follows the session snapshot, so a Settings change
          // mid-session applies to the next session (ADR-0004).
          let session = currentSessionSettings ?? settings.sessionSettings
          if session.historyEnabled, !text.isEmpty {
            // Before the outcome routing: words the paste then loses are
            // exactly the words history exists to keep.
            await dependencies.recordHistory(
              text,
              historySource(for: session.insertionDestination),
              session.historyFolder
            )
          }
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
          if let session = currentSessionSettings,
             session.myvoiceCaptureEnabled,
             !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let localeID = locale(for: activeSlot)?.identifier ?? Locale.current.identifier
            myVoiceService.capture(
              rawTranscript: text, correctedText: text, audioURL: nil,
              startedAt: startedAt, stoppedAt: stoppedAt, localeIdentifier: localeID
            )
          }
          myVoiceSessionStartedAt = nil
          pendingRawTranscript = nil
        }
      } catch {
        fail(message: error.localizedDescription, wasCancelled: false)
      }
      finishTask = nil
    }
  }

  /// The draft and the selection a replacement round began with, so the
  /// round can preview its streaming words into that exact spot, put the
  /// draft back when it delivers nothing, or splice the words over the
  /// selection when it does.
  private var pendingReplacement: DraftReplacement?
  /// The session's accumulated speech time across every round, recorded
  /// when the reviewed draft is pasted.
  private var sessionSpeakingDuration: TimeInterval = 0
  private var pendingRawTranscript: String?
  private var myVoiceSessionStartedAt: Date?

  /// Freezes the draft and the field's selection before the round starts,
  /// so its live words can preview into the draft instead of replacing it.
  private func captureDraftSelection() -> DraftReplacement? {
    guard let hudController else { return nil }
    let draft = hudController.draftText
    let range = hudController.draftSelectionRange
      ?? NSRange(location: draft.utf16.count, length: 0)
    return DraftReplacement(draft: draft, range: range)
  }

  /// Commits a replacement round's recognized text into the held draft: it
  /// replaces exactly the selection the round began with, and the cursor
  /// lands after the inserted words. A round that delivered nothing leaves
  /// the draft untouched.
  private func commitReplacement(_ text: String, into pending: DraftReplacement) {
    pendingReplacement = nil
    guard let hudController else {
      send(.finishCompleted)
      return
    }
    if pending.hasWords(text) {
      let draft = pending.committed(with: text)
      let cursor = String.Index(
        utf16Offset: pending.insertionPointOffset(committing: text),
        in: draft
      )
      hudController.setDraft(draft, selection: TextSelection(insertionPoint: cursor))
    } else {
      // No words delivered: the draft returns untouched, selection where
      // it was, so the user can try again or edit.
      hudController.setDraft(pending.draft)
    }
    send(.finishCompleted)
  }

  /// Puts the HUD back into the review: the field returns with the draft
  /// restored if a replacement round never delivered.
  private func showEditableDraft() {
    if let pending = pendingReplacement {
      pendingReplacement = nil
      hudController?.setDraft(pending.draft)
    }
    hudController?.showEditableDraft()
  }

  /// Return while the draft is under review: the edited draft is delivered
  /// to the session's target exactly like the release flow delivers a
  /// finished session — same service, same clipboard-restore semantics,
  /// same paste sound. The panel resigns key with the retract, which hands
  /// the captured control back its AX focus, so the insertion validates
  /// and pastes into the right place.
  private func pasteDraft() {
    Task { [weak self] in
      guard let self, let hudController else { return }
      // The raw ASR stays the round's first words even when the user edits
      // the draft before Return; the corrected text is what actually lands.
      let startedAt = myVoiceSessionStartedAt ?? Date()
      let stoppedAt = Date()
      let raw = pendingRawTranscript ?? hudController.draftText
      let text = hudController.draftText
      dependencies.hideHUD()
      // Delivery follows the session snapshot, so a Settings change
      // mid-session applies to the next session (ADR-0004).
      let session = currentSessionSettings ?? settings.sessionSettings
      let outcome = await dependencies.insertText(
        text, focusedTarget, session.insertionDestination
      )
      switch outcome {
      case .inserted, .copiedToClipboard:
        dependencies.playPasteSound()
        send(.sessionEnded)
        let wordCount = UsageMetrics.wordCount(in: text)
        await dependencies.recordSession(wordCount, sessionSpeakingDuration)
      case .unavailable:
        send(.sessionEnded)
        dependencies.showMessage("Couldn't insert text", nil)
      }
      if let session = currentSessionSettings,
         session.myvoiceCaptureEnabled,
         !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        let localeID = locale(for: activeSlot)?.identifier ?? Locale.current.identifier
        myVoiceService.capture(
          rawTranscript: raw, correctedText: text, audioURL: nil,
          startedAt: startedAt, stoppedAt: stoppedAt, localeIdentifier: localeID
        )
      }
      pendingRawTranscript = nil
      myVoiceSessionStartedAt = nil
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
        // A replacement round that failed leaves the session back in
        // `.reviewing` with the draft intact; the review coming back IS
        // the signal, and a message would evict it.
        if !machine.isReviewing {
          dependencies.showMessage(message, nil)
        }
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
