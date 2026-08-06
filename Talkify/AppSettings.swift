import Foundation
import Observation

/// The application settings: every user-facing preference in one observable,
/// UserDefaults-backed store. Settings binds to it, the HUD observes it, and
/// nothing else touches UserDefaults for these keys.
///
/// The key strings predate this module and must not change — they are what
/// existing users' picks are stored under (and, for sounds, the rawValue also
/// prefixes the bundled asset names).
@MainActor
@Observable
final class AppSettings {
    private enum Keys {
        static let soundSet = "dictationSoundSet"
        static let voiceVisual = "hudVoiceVisual"
        static let waveformStyle = "hudWaveformStyle"
        static let revealStyle = "hudRevealStyle"
        static let longDraftStyle = "hudLongDraftStyle"
        static let glowPalette = "hudGlowPalette"
    }

    @ObservationIgnored
    private let defaults: UserDefaults

    var soundSet: DictationSoundSet {
        didSet { defaults.set(soundSet.rawValue, forKey: Keys.soundSet) }
    }

    var voiceVisual: HUDVoiceVisualStyle {
        didSet { defaults.set(voiceVisual.rawValue, forKey: Keys.voiceVisual) }
    }

    var waveformStyle: HUDWaveformStyle {
        didSet { defaults.set(waveformStyle.rawValue, forKey: Keys.waveformStyle) }
    }

    var revealStyle: HUDRevealStyle {
        didSet { defaults.set(revealStyle.rawValue, forKey: Keys.revealStyle) }
    }

    var longDraftStyle: HUDLongDraftStyle {
        didSet { defaults.set(longDraftStyle.rawValue, forKey: Keys.longDraftStyle) }
    }

    var glowPalette: HUDGlowPalette {
        didSet { defaults.set(glowPalette.rawValue, forKey: Keys.glowPalette) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        soundSet = Self.stored(in: defaults, key: Keys.soundSet) ?? .synth8
        voiceVisual = Self.stored(in: defaults, key: Keys.voiceVisual) ?? .waveform
        waveformStyle = Self.stored(in: defaults, key: Keys.waveformStyle) ?? .chartLine
        revealStyle = Self.stored(in: defaults, key: Keys.revealStyle) ?? .slide
        longDraftStyle = Self.stored(in: defaults, key: Keys.longDraftStyle) ?? .growDown
        glowPalette = Self.stored(in: defaults, key: Keys.glowPalette) ?? .spectrum
    }

    private static func stored<Value: RawRepresentable<String>>(
        in defaults: UserDefaults,
        key: String
    ) -> Value? {
        defaults.string(forKey: key).flatMap { Value(rawValue: $0) }
    }
}
