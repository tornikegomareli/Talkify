import AppKit
import AVFAudio

/// Read Aloud: speaks the focused application's selected text with the
/// Settings-picked voice. Apple speech synthesis only (CONTEXT.md: Apple
/// frameworks only); playback is on-device and offline. Errors surface
/// through the HUD message surface, matching Direct Dictation.
@MainActor
final class ReadAloudController: NSObject {
    /// Follows the synthesizer's actual state; the status menu mirrors it.
    var onSpeakingStateChange: ((Bool) -> Void)?

    private let settings: AppSettings
    private let hudController: DictationHUDController
    /// Its own service instance: Read Aloud only reads the focused
    /// element's selection and never inserts.
    private let textService = TextInsertionService()
    private let synthesizer = AVSpeechSynthesizer()

    init(settings: AppSettings, hudController: DictationHUDController) {
        self.settings = settings
        self.hudController = hudController
        super.init()
        synthesizer.delegate = self
    }

    func toggle() {
        if synthesizer.isSpeaking {
            stop()
        } else {
            speakSelection()
        }
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func speakSelection() {
        guard PermissionService.hasAccessibilityAccess else {
            hudController.showMessage("Accessibility permission required")
            return
        }

        let selection = textService.captureSelectedText()?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let selection, !selection.isEmpty else {
            hudController.showMessage("No text selected")
            return
        }

        let utterance = AVSpeechUtterance(string: selection)
        if !settings.readAloudVoiceID.isEmpty,
           let voice = AVSpeechSynthesisVoice(identifier: settings.readAloudVoiceID) {
            utterance.voice = voice
        }
        synthesizer.speak(utterance)
    }
}

extension ReadAloudController: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didStart utterance: AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in
            self?.onSpeakingStateChange?(true)
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in
            self?.onSpeakingStateChange?(false)
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in
            self?.onSpeakingStateChange?(false)
        }
    }
}
