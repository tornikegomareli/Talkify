import AppKit

/// The sound sets a session can use. Licensing differs per set — see
/// Resources/Sounds/LICENSE-SOUNDS.txt before shipping (Pop is CC-BY-NC and
/// must be replaced or dropped before release).
///
/// rawValue is load-bearing twice over: it is the UserDefaults value existing
/// picks are stored under, and it prefixes the bundled asset names
/// (`<rawValue>Begin/End/Paste.wav`). Renaming a case breaks both.
enum DictationSoundSet: String, CaseIterable {
    /// Plunger pop (freesound #321807, CC-BY-NC — placeholder, not shippable).
    case pop = "Pop"
    /// Minimal 7ms UI click (freesound #370962, CC0).
    case click = "Click"
    /// Our own synthesized two-note pluck: rising fifth in, falling fifth
    /// out. Original asset, no license constraints.
    case chime = "Chime"
    /// Synthesized double-strike tock-tick with a singing tail, in the style
    /// of a reference app's v3 pair. Original asset.
    case synth3 = "Synth3"
    /// Synthesized single woody tock, tick-then-tock out, in the style of the
    /// reference app's v7 pair. Original asset.
    case synth7 = "Synth7"
    /// Synthesized rising thump-blip-body gesture in, falling body-thump out,
    /// in the style of the reference app's synth8 trio. Original asset.
    case synth8 = "Synth8"

    var isShippable: Bool {
        self != .pop
    }

    static var settingsCases: [Self] {
#if DEBUG
        allCases
#else
        allCases.filter { $0.isShippable }
#endif
    }
}

/// The sounds that bracket a Direct Dictation session: begin when listening
/// starts, end when the session closes, paste when text lands in the target.
/// Callers supply the captured or live set. Assets reload lazily when that
/// set changes.
@MainActor
final class DictationHUDSounds {
    private var loadedSet: DictationSoundSet?
    private var begin: NSSound?
    private var end: NSSound?
    private var paste: NSSound?

    func playBegin(using set: DictationSoundSet) {
        play(\.begin, using: set)
    }

    func playEnd(using set: DictationSoundSet) {
        play(\.end, using: set)
    }

    func playPaste(using set: DictationSoundSet) {
        play(\.paste, using: set)
    }

    func beginDuration(for set: DictationSoundSet) -> TimeInterval {
        loadIfNeeded(set)
        return begin?.duration ?? 0
    }

    func hasPreviewSounds(for set: DictationSoundSet) -> Bool {
        loadIfNeeded(set)
        return begin != nil && end != nil
    }

    func stopAll() {
        begin?.stop()
        end?.stop()
        paste?.stop()
    }

    private func play(
        _ sound: KeyPath<DictationHUDSounds, NSSound?>,
        using set: DictationSoundSet
    ) {
        loadIfNeeded(set)
        guard let sound = self[keyPath: sound] else { return }
        sound.stop()
        sound.volume = 0.5
        sound.play()
    }

    private func loadIfNeeded(_ set: DictationSoundSet) {
        guard set != loadedSet else { return }
        stopAll()
        begin = NSSound.bundled("\(set.rawValue)Begin")
        end = NSSound.bundled("\(set.rawValue)End")
        paste = NSSound.bundled("\(set.rawValue)Paste")
        loadedSet = set
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
