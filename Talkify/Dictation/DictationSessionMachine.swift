import Foundation

/// The Direct Dictation session's state machine as a pure reducer: actions
/// in, state transition inside, effects out. No clocks (instants ride in on
/// actions), no services, no tasks — which is what makes the gesture and
/// race rules (quick-tap latching, finish-queued-while-starting,
/// cancel-while-starting, the no-speech policy) unit-testable
/// (DictationSessionMachineTests).
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
        case startNoSpeechTimer
        case stopNoSpeechTimer
        case showListening(latched: Bool)
        case showLatched
        case showLiveText
        case showFinalizing
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

    var isSessionActive: Bool {
        state != .idle
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
            return hasSpeech ? [] : cancel()
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
        case .idle, .starting(.latched), .recording(.latched), .finishing, .cancelling:
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
        case .finishing, .cancelling:
            return []
        }
    }

    private mutating func beginApproved() -> [Effect] {
        guard state == .idle, let gesture = pendingGesture else { return [] }
        pendingGesture = nil
        state = .starting(gesture)
        hasSpeech = false
        finishWhenStarted = false
        cancelWhenStarted = false
        recordingStartedAt = nil
        return [
            .setEscapeCapture(true),
            .showListening(latched: gesture.isLatched),
            .notifyRecording(true),
            .beginRecognition,
        ]
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
        case .idle, .recording, .finishing, .cancelling:
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
        if state == .finishing {
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

    private mutating func cancel() -> [Effect] {
        switch state {
        case .idle, .finishing, .cancelling:
            return []
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

    private mutating func reset() -> [Effect] {
        state = .idle
        pendingGesture = nil
        hasSpeech = false
        finishWhenStarted = false
        cancelWhenStarted = false
        recordingStartedAt = nil
        return [.stopNoSpeechTimer, .setEscapeCapture(false), .notifyRecording(false)]
    }

    private static func timeInterval(for duration: Duration) -> TimeInterval {
        let components = duration.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
