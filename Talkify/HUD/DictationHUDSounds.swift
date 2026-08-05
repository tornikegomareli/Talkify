import AppKit

/// The two bumps that bracket a Direct Dictation session: a rising one when
/// listening starts, a falling one when the session ends. Kenney's Interface
/// Sounds, CC0 (see Resources/Sounds/LICENSE-Kenney-CC0.txt).
@MainActor
final class DictationHUDSounds {
    private let begin = NSSound.bundled("DictationBegin")
    private let end = NSSound.bundled("DictationEnd")

    func playBegin() {
        play(begin)
    }

    func playEnd() {
        play(end)
    }

    private func play(_ sound: NSSound?) {
        guard let sound else { return }
        sound.stop()
        sound.volume = 0.5
        sound.play()
    }
}

private extension NSSound {
    static func bundled(_ name: String) -> NSSound? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else {
            return nil
        }
        return NSSound(contentsOf: url, byReference: true)
    }
}
