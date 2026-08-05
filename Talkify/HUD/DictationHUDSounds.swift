import AppKit

/// The candidate sound sets, selectable from the debug menu today and from
/// Settings later — the selection persists under `Keys.soundSet` so the
/// future Settings UI reads and writes the same value. Licensing differs per
/// set — see Resources/Sounds/LICENSE-SOUNDS.txt before shipping.
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
}

/// The sounds that bracket a Direct Dictation session: begin when listening
/// starts, end when the session closes, paste when text lands in the target.
@MainActor
final class DictationHUDSounds {
    private enum Keys {
        static let soundSet = "dictationSoundSet"
    }

    var set: DictationSoundSet {
        didSet {
            UserDefaults.standard.set(set.rawValue, forKey: Keys.soundSet)
            load()
        }
    }

    private var begin: NSSound?
    private var end: NSSound?
    private var paste: NSSound?

    init() {
        let stored = UserDefaults.standard.string(forKey: Keys.soundSet)
        set = stored.flatMap(DictationSoundSet.init(rawValue:)) ?? .pop
        load()
    }

    func playBegin() {
        play(begin)
    }

    func playEnd() {
        play(end)
    }

    func playPaste() {
        play(paste)
    }

    private func load() {
        begin = NSSound.bundled("\(set.rawValue)Begin")
        end = NSSound.bundled("\(set.rawValue)End")
        paste = NSSound.bundled("\(set.rawValue)Paste")
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
