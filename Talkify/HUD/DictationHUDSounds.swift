import AppKit

/// The candidate sound pairs for the session bumps, kept side by side while
/// the pick is judged by ear from the debug menu. Licensing differs per set —
/// see Resources/Sounds/LICENSE-SOUNDS.txt before shipping either.
enum DictationSoundSet: String, CaseIterable {
    /// Plunger pop (freesound #321807, CC-BY-NC — placeholder, not shippable).
    case pop = "Pop"
    /// Minimal 7ms UI click (freesound #370962, CC0).
    case click = "Click"
    /// Our own synthesized two-note pluck: rising fifth in, falling fifth
    /// out. Original asset, no license constraints.
    case chime = "Chime"
}

/// The two bumps that bracket a Direct Dictation session: one when listening
/// starts, a lower-pitched sibling when the session ends.
@MainActor
final class DictationHUDSounds {
    var set = DictationSoundSet.pop {
        didSet { load() }
    }

    private var begin: NSSound?
    private var end: NSSound?

    init() {
        load()
    }

    func playBegin() {
        play(begin)
    }

    func playEnd() {
        play(end)
    }

    private func load() {
        begin = NSSound.bundled("\(set.rawValue)Begin")
        end = NSSound.bundled("\(set.rawValue)End")
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
