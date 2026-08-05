import AppKit

/// The two bumps that bracket a Direct Dictation session: a pop when
/// listening starts, a lower pop when the session ends. Current assets are
/// placeholders under a non-commercial license — see
/// Resources/Sounds/LICENSE-SOUNDS.txt before shipping.
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
