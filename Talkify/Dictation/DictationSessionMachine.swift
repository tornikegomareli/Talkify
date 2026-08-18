import Foundation

/// The Direct Dictation session's state machine as a pure reducer: actions
/// in, state transition inside, effects out. No clocks (instants ride in on
/// actions), no services, no tasks — which is what makes the gesture and
/// race rules (quick-tap latching, finish-queued-while-starting,
/// cancel-while-starting, the no-speech policy) unit-testable
/// (DictationSessionMachineTests).
///
/// The editable-draft variant adds the `.reviewing` state: recognition
/// finished, the draft held in the HUD until Return pastes it, the trigger
/// starts a replacement round, or Escape discards it. The variant itself is
/// not a machine concern — the controller encodes it by sending
/// `.finishCompleted` instead of `.sessionEnded` once recognition finishes.
/// Replacement rounds reuse the starting/recording/finishing states; the
/// `reviewRound` flag marks one so a round that never delivers (no speech,
/// a dead recognizer) returns to `.reviewing` with the draft intact, where
/// an Escape discards everything.
///
/// DirectDictationController owns the impure half: it translates monitor
/// events into actions, runs the begin guards, and executes the returned
/// effects against the speech service, HUD, and insertion. Async completions
/// come back as new actions. (ADR-0006: MV + local reducers.)
struct DictationSessionMachine {
  enum Gesture: Equatable {
    case held(startedAt: ContinuousClock.Instant)
    case latched

    var isLatched: Bool {
      if case .latched = self { return true }
      return false
    }
  }

  enum State: Equatable {
    case idle
    case starting(Gesture)
    case recording(Gesture)
    case finishing
    /// The editable-draft variant holds the finished draft here until
    /// Return pastes it, the trigger starts a replacement round, or Escape
    /// discards it.
    case reviewing
    case cancelling
  }

  enum Action: Equatable {
    case triggerPressed(now: ContinuousClock.Instant)
    case triggerReleased(now: ContinuousClock.Instant)
    case menuToggled(now: ContinuousClock.Instant)
    case escapePressed
    case readAloudPressed
    /// The controller's begin guards (prepared, permissions, secure
    /// field) passed and the target is captured.
    case beginApproved
    case beginRejected
    case recognitionStarted(now: ContinuousClock.Instant)
    /// Recognition failed while starting, finishing, or mid-session.
    /// `wasCancelled` covers the torn-down start task.
    case recognitionFailed(wasCancelled: Bool)
    case updateReceived(hasVisibleText: Bool)
    case noSpeechTimedOut
    /// Recognition finished and the editable-draft variant holds the text
    /// for review instead of inserting it. Sent by the controller in place
    /// of `.sessionEnded`; moves `.finishing` to `.reviewing`.
    case finishCompleted
    /// Return pressed while the draft is under review: paste it.
    case returnPressed
    /// The terminal reset after a finish inserted, a cancel completed,
    /// or a failure was shown.
    case sessionEnded
  }

  enum Effect: Equatable {
    /// Run the begin guards; feed back `beginApproved` or `beginRejected`.
    case checkAndBegin
    case beginRecognition
    case finishRecognition(speakingDuration: TimeInterval)
    case cancelRecognition
    case cancelStartTask
    case setEscapeCapture(Bool)
    /// Plain Return is swallowed while the draft is under review, so the
    /// field can never insert a newline where the user asked to paste.
    /// Modified Return (⌥↩) passes through and inserts one.
    case setReturnCapture(Bool)
    case startNoSpeechTimer
    case stopNoSpeechTimer
    case showListening(latched: Bool)
    case showLatched
    case showLiveText
    case showFinalizing
    /// Swap the HUD's read-only band for the editable draft field and give
    /// the panel key (the editable-draft variant's reviewing state).
    case showEditableDraft
    /// Insert the reviewed draft into the session's target, exactly like a
    /// released session's insertion (same service, same clipboard-restore
    /// semantics, same paste sound).
    case pasteDraft
    case hideHUD
    case notifyRecording(Bool)
    case triggerReadAloud
  }

  /// Releasing the trigger before this counts as a quick tap and latches
  /// the session (CONTEXT.md).
  static let tapThreshold = Duration.milliseconds(250)

  private(set) var state = State.idle

  private var pendingGesture: Gesture?
  private var hasSpeech = false
  private var finishWhenStarted = false
  private var cancelWhenStarted = false
  private var recordingStartedAt: ContinuousClock.Instant?
  /// True while a replacement round (started from `.reviewing`) is in
  /// flight. A round that ends without delivering returns to `.reviewing`
  /// with the draft intact; an Escape clears it so the whole session ends.
  private var reviewRound = false

  var isSessionActive: Bool {
    state != .idle
  }

  /// Whether the draft is currently held for editing (the editable-draft
  /// variant). The controller branches its begin guards on this: a
  /// replacement round must not recapture the outer target.
  var isReviewing: Bool {
    state == .reviewing
  }

  mutating func reduce(_ action: Action) -> [Effect] {
    switch action {
    case let .triggerPressed(now):
      return triggerPressed(now: now)
    case let .triggerReleased(now):
      return triggerReleased(now: now)
    case let .menuToggled(now):
      return menuToggled(now: now)
    case .escapePressed:
      // Escape ends the whole session, draft included: while the draft is
      // under review, or a replacement round is in flight, it discards
      // rather than resurrecting the review.
      reviewRound = false
      return cancel()
    case .readAloudPressed:
      return state == .idle ? [.triggerReadAloud] : []
    case .beginApproved:
      return beginApproved()
    case .beginRejected:
      pendingGesture = nil
      return []
    case let .recognitionStarted(now):
      return recognitionStarted(now: now)
    case let .recognitionFailed(wasCancelled):
      return recognitionFailed(wasCancelled: wasCancelled)
    case let .updateReceived(hasVisibleText):
      return updateReceived(hasVisibleText: hasVisibleText)
    case .noSpeechTimedOut:
      if hasSpeech { return [] }
      return reviewRound ? abortReplacementRound() : cancel()
    case .finishCompleted:
      return finishCompleted()
    case .returnPressed:
      return returnPressed()
    case .sessionEnded:
      return reset()
    }
  }

  private mutating func triggerPressed(now: ContinuousClock.Instant) -> [Effect] {
    switch state {
    case .idle:
      pendingGesture = .held(startedAt: now)
      return [.checkAndBegin]
    case .starting(.latched):
      finishWhenStarted = true
      return []
    case .recording(.latched):
      return finish(now: now)
    case .reviewing:
      // A replacement round: the draft stays held and the recognizer
      // listens for the words that will replace the selection. The
      // controller's begin guards skip the outer target capture for it.
      reviewRound = true
      pendingGesture = .held(startedAt: now)
      return [.checkAndBegin]
    case .starting(.held), .recording(.held), .finishing, .cancelling:
      return []
    }
  }

  private mutating func triggerReleased(now: ContinuousClock.Instant) -> [Effect] {
    switch state {
    case let .starting(.held(startedAt)):
      if startedAt.duration(to: now) < Self.tapThreshold {
        state = .starting(.latched)
        return [.showLatched]
      }
      finishWhenStarted = true
      return []
    case let .recording(.held(startedAt)):
      if startedAt.duration(to: now) < Self.tapThreshold {
        state = .recording(.latched)
        return [.showLatched]
      }
      return finish(now: now)
    case .idle, .reviewing, .starting(.latched), .recording(.latched), .finishing, .cancelling:
      return []
    }
  }

  private mutating func menuToggled(now: ContinuousClock.Instant) -> [Effect] {
    switch state {
    case .idle:
      pendingGesture = .latched
      return [.checkAndBegin]
    case .starting:
      finishWhenStarted = true
      return []
    case .recording:
      return finish(now: now)
    case .reviewing:
      // The menu's Stop Dictation ends the review like Return: the draft
      // is pasted rather than discarded.
      return returnPressed()
    case .finishing, .cancelling:
      return []
    }
  }

  private mutating func beginApproved() -> [Effect] {
    let fromReview = state == .reviewing
    guard state == .idle || fromReview, let gesture = pendingGesture else { return [] }
    pendingGesture = nil
    state = .starting(gesture)
    hasSpeech = false
    finishWhenStarted = false
    cancelWhenStarted = false
    recordingStartedAt = nil
    var effects: [Effect] = [
      .setEscapeCapture(true),
      .showListening(latched: gesture.isLatched),
      .notifyRecording(true),
      .beginRecognition,
    ]
    if fromReview {
      // The replacement round hides the editable field, so Return stops
      // meaning paste for as long as the round runs.
      effects.insert(.setReturnCapture(false), at: 1)
    }
    return effects
  }

  private mutating func recognitionStarted(now: ContinuousClock.Instant) -> [Effect] {
    if cancelWhenStarted {
      // Escape landed while the recognizer was still spinning up; the
      // session is already .cancelling and the HUD already hidden.
      return [.cancelRecognition]
    }

    switch state {
    case let .starting(gesture):
      state = .recording(gesture)
      recordingStartedAt = now
      var effects: [Effect] = [.startNoSpeechTimer]
      if finishWhenStarted {
        effects += finish(now: now)
      }
      return effects
    case .idle, .recording, .finishing, .cancelling, .reviewing:
      return []
    }
  }

  private mutating func recognitionFailed(wasCancelled: Bool) -> [Effect] {
    if wasCancelled || cancelWhenStarted {
      return reset()
    }
    guard isSessionActive else { return [] }
    state = .cancelling
    return [
      .stopNoSpeechTimer,
      .setEscapeCapture(false),
      .cancelRecognition,
    ]
  }

  private mutating func updateReceived(hasVisibleText: Bool) -> [Effect] {
    guard isSessionActive else { return [] }

    var effects: [Effect] = []
    if hasVisibleText {
      hasSpeech = true
      effects.append(.stopNoSpeechTimer)
    }

    // The recognizer emits its final results while the session finishes;
    // the band already says "Finalizing…" and must not flash the draft.
    // While the draft is under review nothing is recognized, so no live
    // text may overwrite the field either.
    if state == .finishing || state == .reviewing {
      return effects
    }
    effects.append(.showLiveText)
    return effects
  }

  private mutating func finish(now: ContinuousClock.Instant) -> [Effect] {
    guard case .recording = state else { return [] }
    let speakingDuration = recordingStartedAt.map {
      Self.timeInterval(for: $0.duration(to: now))
    } ?? 0
    state = .finishing
    return [
      .stopNoSpeechTimer,
      .setEscapeCapture(false),
      .showFinalizing,
      .finishRecognition(speakingDuration: speakingDuration),
    ]
  }

  private mutating func returnPressed() -> [Effect] {
    guard state == .reviewing else { return [] }
    // `.finishing` doubles as the paste-in-flight wait: the session has
    // ended but the terminal reset awaits the insertion outcome, exactly
    // like a released session's finish.
    state = .finishing
    reviewRound = false
    return [.setEscapeCapture(false), .setReturnCapture(false), .pasteDraft]
  }

  private mutating func finishCompleted() -> [Effect] {
    guard state == .finishing else { return [] }
    state = .reviewing
    reviewRound = false
    return [.setEscapeCapture(true), .setReturnCapture(true), .showEditableDraft]
  }

  private mutating func cancel() -> [Effect] {
    switch state {
    case .idle, .finishing, .cancelling:
      return []
    case .reviewing:
      // Unreachable in practice (the no-speech timer never runs while
      // reviewing), but the discard must not resurrect the review.
      reviewRound = false
      return discardReview()
    case .starting:
      // The start task tears itself down and reports back as a
      // cancelled recognition failure.
      cancelWhenStarted = true
      state = .cancelling
      return [.cancelStartTask, .stopNoSpeechTimer, .setEscapeCapture(false), .hideHUD]
    case .recording:
      state = .cancelling
      return [.stopNoSpeechTimer, .setEscapeCapture(false), .hideHUD, .cancelRecognition]
    }
  }

  /// A replacement round that never heard anything: the round dies, but
  /// the review survives with the draft intact. The reset that follows the
  /// cancelled recognition moves back to `.reviewing` instead of `.idle`.
  private mutating func abortReplacementRound() -> [Effect] {
    state = .cancelling
    return [.stopNoSpeechTimer, .setEscapeCapture(false), .cancelRecognition]
  }

  /// Escape while the draft is under review: discard the draft, paste
  /// nothing, end the session exactly like a cancel.
  private mutating func discardReview() -> [Effect] {
    reviewRound = false
    let terminal = reset()
    return terminal + [.hideHUD]
  }

  private mutating func reset() -> [Effect] {
    if reviewRound, state == .cancelling {
      // The round ended without delivering; the draft is still held.
      reviewRound = false
      state = .reviewing
      return [
        .stopNoSpeechTimer,
        .setEscapeCapture(true),
        .setReturnCapture(true),
        .showEditableDraft,
      ]
    }
    state = .idle
    pendingGesture = nil
    hasSpeech = false
    finishWhenStarted = false
    cancelWhenStarted = false
    recordingStartedAt = nil
    return [
      .stopNoSpeechTimer,
      .setEscapeCapture(false),
      .setReturnCapture(false),
      .notifyRecording(false),
    ]
  }

  private static func timeInterval(for duration: Duration) -> TimeInterval {
    let components = duration.components
    return Double(components.seconds) + Double(components.attoseconds) / 1e18
  }
}
