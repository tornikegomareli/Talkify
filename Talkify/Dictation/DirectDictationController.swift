import AppKit

@MainActor
final class DirectDictationController {
    var onRecordingStateChange: ((Bool) -> Void)?

    private enum Gesture {
        case held(startedAt: ContinuousClock.Instant)
        case latched

        var isLatched: Bool {
            if case .latched = self { return true }
            return false
        }
    }

    private enum State {
        case idle
        case starting(Gesture)
        case recording(Gesture)
        case finishing
        case cancelling
    }

    private static let tapThreshold = Duration.milliseconds(250)
    private static let noSpeechTimeout = Duration.seconds(15)

    private let settings: AppSettings
    private let speechService = SpeechRecognitionService()
    private let hudController: DictationHUDController
    private let textInsertionService = TextInsertionService()

    private var triggerMonitor: DictationTriggerMonitor?
    private var state = State.idle
    private var focusedTarget: TextInsertionService.Target?
    private var noSpeechTask: Task<Void, Never>?
    private var permissionTask: Task<Void, Never>?
    private var sessionStartTask: Task<Void, Never>?
    private var hasSpeech = false
    private var finishWhenStarted = false
    private var cancelWhenStarted = false
    private var isPrepared = false
    private var preparationFailureMessage: String?

    init(settings: AppSettings, hudController: DictationHUDController) {
        self.settings = settings
        self.hudController = hudController
        triggerMonitor = DictationTriggerMonitor { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handle(event)
            }
        }
    }

    func start() {
        requestPermissionsAndPrepare()
    }

    func stop() {
        noSpeechTask?.cancel()
        permissionTask?.cancel()
        sessionStartTask?.cancel()
        triggerMonitor?.stop()
        isPrepared = false

        Task {
            await speechService.shutDown()
        }
    }

    func toggleFromMenu() {
        switch state {
        case .idle:
            beginSession(gesture: .latched)
        case .starting, .recording:
            requestFinish()
        case .finishing, .cancelling:
            break
        }
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

    private func handle(_ event: DictationTriggerMonitor.Event) {
        switch event {
        case .triggerPressed:
            triggerPressed()
        case .triggerReleased:
            triggerReleased()
        case .cancelPressed:
            cancelSession()
        }
    }

    private func triggerPressed() {
        switch state {
        case .idle:
            beginSession(gesture: .held(startedAt: .now))
        case .starting(.latched), .recording(.latched):
            requestFinish()
        case .starting(.held), .recording(.held), .finishing, .cancelling:
            break
        }
    }

    private func triggerReleased() {
        switch state {
        case let .starting(.held(startedAt)):
            updateReleasedGesture(startedAt: startedAt, isStarting: true)
        case let .recording(.held(startedAt)):
            updateReleasedGesture(startedAt: startedAt, isStarting: false)
        case .idle, .starting(.latched), .recording(.latched), .finishing, .cancelling:
            break
        }
    }

    private func updateReleasedGesture(
        startedAt: ContinuousClock.Instant,
        isStarting: Bool
    ) {
        let elapsed = startedAt.duration(to: .now)
        if elapsed < Self.tapThreshold {
            state = isStarting ? .starting(.latched) : .recording(.latched)
            hudController.showLatched()
        } else {
            requestFinish()
        }
    }

    private func beginSession(gesture: Gesture) {
        guard case .idle = state else { return }

        guard isPrepared else {
            hudController.showMessage(preparationFailureMessage ?? "Preparing speech…")
            return
        }

        if !PermissionService.hasAccessibilityAccess {
            PermissionService.requestAccessibilityAccess()
            hudController.showMessage("Accessibility permission required")
            return
        }

        let target = textInsertionService.captureFocusedTarget()
        if target?.isSecure == true {
            hudController.showMessage("Secure field", on: target?.displayID)
            return
        }

        state = .starting(gesture)
        focusedTarget = target
        hasSpeech = false
        finishWhenStarted = false
        cancelWhenStarted = false
        triggerMonitor?.setEscapeCaptureEnabled(true)
        let sessionSettings = settings.sessionSettings
        hudController.showListening(
            on: target?.displayID,
            isLatched: gesture.isLatched,
            settings: sessionSettings
        )
        onRecordingStateChange?(true)

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
                            self?.failSession(message: message)
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
                    resetSession()
                    return
                }
                sessionStartTask = nil
                recognitionDidStart()
            } catch {
                sessionStartTask = nil
                if Task.isCancelled || cancelWhenStarted {
                    resetSession()
                    return
                }
                failSession(message: error.localizedDescription)
            }
        }
    }

    private func recognitionDidStart() {
        if cancelWhenStarted {
            Task { [weak self] in
                guard let self else { return }
                await speechService.cancel()
                resetSession()
            }
            return
        }

        switch state {
        case let .starting(gesture):
            state = .recording(gesture)
            startNoSpeechTimer()
            if finishWhenStarted {
                requestFinish()
            }
        case .idle, .recording, .finishing, .cancelling:
            break
        }
    }

    private func receive(_ update: SpeechRecognitionService.Update) {
        guard isSessionActive else { return }

        let displayText = update.displayText
        if !displayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            hasSpeech = true
            noSpeechTask?.cancel()
            noSpeechTask = nil
        }

        // The recognizer emits its final results while the session finishes;
        // the band already says "Finalizing…" and must not flash the draft.
        if case .finishing = state { return }
        hudController.showLiveText(displayText)
    }

    private func requestFinish() {
        switch state {
        case .starting:
            finishWhenStarted = true
        case .recording:
            finishSession()
        case .idle, .finishing, .cancelling:
            break
        }
    }

    private func finishSession() {
        guard case .recording = state else { return }
        state = .finishing
        stopNoSpeechTimer()
        triggerMonitor?.setEscapeCaptureEnabled(false)
        hudController.showFinalizing()

        Task { [weak self] in
            guard let self else { return }
            do {
                let text = try await speechService.finish()
                hudController.hide()
                await textInsertionService.insert(text, into: focusedTarget)
                hudController.playPasteSound()
                resetSession()
            } catch {
                failSession(message: error.localizedDescription)
            }
        }
    }

    private func cancelSession() {
        switch state {
        case .idle, .finishing, .cancelling:
            return
        case .starting:
            cancelWhenStarted = true
            state = .cancelling
            sessionStartTask?.cancel()
        case .recording:
            state = .cancelling
        }

        stopNoSpeechTimer()
        triggerMonitor?.setEscapeCaptureEnabled(false)
        hudController.hide()

        if sessionStartTask == nil {
            Task { [weak self] in
                guard let self else { return }
                await speechService.cancel()
                resetSession()
            }
        }
    }

    private func cancelSilentSession() {
        guard !hasSpeech else { return }
        cancelSession()
    }

    private func failSession(message: String) {
        guard isSessionActive else { return }
        state = .cancelling
        stopNoSpeechTimer()
        triggerMonitor?.setEscapeCaptureEnabled(false)

        Task { [weak self] in
            guard let self else { return }
            await speechService.cancel()
            resetSession()
            hudController.showMessage(message)
        }
    }

    private func startNoSpeechTimer() {
        noSpeechTask?.cancel()
        noSpeechTask = Task { [weak self] in
            try? await Task.sleep(for: Self.noSpeechTimeout)
            guard !Task.isCancelled else { return }
            self?.cancelSilentSession()
        }
    }

    private func stopNoSpeechTimer() {
        noSpeechTask?.cancel()
        noSpeechTask = nil
    }

    private func resetSession() {
        stopNoSpeechTimer()
        state = .idle
        focusedTarget = nil
        hasSpeech = false
        finishWhenStarted = false
        cancelWhenStarted = false
        sessionStartTask = nil
        triggerMonitor?.setEscapeCaptureEnabled(false)
        onRecordingStateChange?(false)
    }

    private func installTriggerMonitor() {
        let installed = triggerMonitor?.start() == true
        guard installed else {
            hudController.showMessage("Accessibility permission required")
            return
        }
    }

    private func preparationFailed(message: String) {
        preparationFailureMessage = message
        hudController.showMessage(message)
    }

    private var isSessionActive: Bool {
        switch state {
        case .idle:
            false
        case .starting, .recording, .finishing, .cancelling:
            true
        }
    }
}
