import AppKit
import AVFAudio
import Observation

/// The Apple synthesis voices Read Aloud offers: enhanced and premium
/// qualities, plus the user's Personal Voice once authorized. Default-quality
/// voices are excluded — they undersell the feature. Siri voices never appear:
/// Apple does not expose them to third-party apps.
///
/// Talkify cannot download voices (no public API); Settings deep-links the
/// user to System Settings instead, and this catalog refreshes itself the
/// moment a download finishes via `availableVoicesDidChangeNotification`.
@MainActor
@Observable
final class VoiceCatalog {
    private(set) var voices: [AVSpeechSynthesisVoice] = []

    @ObservationIgnored
    private nonisolated(unsafe) var observer: (any NSObjectProtocol)?

    init() {
        refresh()
        observer = NotificationCenter.default.addObserver(
            forName: AVSpeechSynthesizer.availableVoicesDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func refresh() {
        voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { voice in
                voice.quality == .enhanced
                    || voice.quality == .premium
                    || voice.voiceTraits.contains(.isPersonalVoice)
            }
            .sorted { lhs, rhs in
                if lhs.quality != rhs.quality {
                    return lhs.quality.rawValue > rhs.quality.rawValue
                }
                return lhs.name < rhs.name
            }
    }

    /// A picker label: "Ava · English (US) · Premium".
    nonisolated static func label(for voice: AVSpeechSynthesisVoice) -> String {
        let language = Locale.current.localizedString(forIdentifier: voice.language)
            ?? voice.language
        return "\(voice.name) · \(language) · \(qualityLabel(for: voice))"
    }

    nonisolated static func qualityLabel(for voice: AVSpeechSynthesisVoice) -> String {
        if voice.voiceTraits.contains(.isPersonalVoice) { return "Personal" }
        switch voice.quality {
        case .premium: return "Premium"
        case .enhanced: return "Enhanced"
        default: return "Default"
        }
    }

    /// Opens the pane where the user downloads voices. There is no API to
    /// download or even enumerate not-yet-installed voices, so the handoff
    /// is the whole story; the legacy anchor is tried first, then the
    /// Accessibility root as a fallback.
    static func openVoiceDownloadSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.universalaccess?SpokenContent",
            "x-apple.systempreferences:com.apple.Accessibility-Settings.extension",
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    /// Opens the Personal Voice pane, where the user creates a voice trained
    /// on their own speech. Creation has no API at all — the recording and
    /// training flow is exclusively Apple's UI — so this link is the entire
    /// integration; Talkify can only request to use the result.
    static func openPersonalVoiceSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.Accessibility-Settings.extension?PersonalVoice",
            "x-apple.systempreferences:com.apple.preference.universalaccess?PersonalVoice",
            "x-apple.systempreferences:com.apple.Accessibility-Settings.extension",
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    static func requestPersonalVoiceAccess() async -> AVSpeechSynthesizer.PersonalVoiceAuthorizationStatus {
        await withCheckedContinuation { continuation in
            AVSpeechSynthesizer.requestPersonalVoiceAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
}
