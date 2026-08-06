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
        // Glow Lab (prototype): delete with the lab once the picks are
        // made (#12). Prefixed so they never collide with real keys.
        static let glowPalette = "glowLabPalette"
        static let glowVoiceBrightness = "glowLabVoiceBrightness"
        static let glowVoiceThickness = "glowLabVoiceThickness"
        static let glowVoiceReach = "glowLabVoiceReach"
        static let glowVoiceParticleCount = "glowLabVoiceParticleCount"
        static let glowVoiceParticleSize = "glowLabVoiceParticleSize"
        static let glowSyllableBursts = "glowLabSyllableBursts"
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

    // Glow Lab (prototype): feel-test knobs for the Edge Glow, controlled
    // from Settings. Delete with the lab once the picks are made (#12).

    var glowPalette: HUDGlowPalette {
        didSet { defaults.set(glowPalette.rawValue, forKey: Keys.glowPalette) }
    }

    var glowVoiceBrightness: Bool {
        didSet { defaults.set(glowVoiceBrightness, forKey: Keys.glowVoiceBrightness) }
    }

    var glowVoiceThickness: Bool {
        didSet { defaults.set(glowVoiceThickness, forKey: Keys.glowVoiceThickness) }
    }

    var glowVoiceReach: Bool {
        didSet { defaults.set(glowVoiceReach, forKey: Keys.glowVoiceReach) }
    }

    var glowVoiceParticleCount: Bool {
        didSet { defaults.set(glowVoiceParticleCount, forKey: Keys.glowVoiceParticleCount) }
    }

    var glowVoiceParticleSize: Bool {
        didSet { defaults.set(glowVoiceParticleSize, forKey: Keys.glowVoiceParticleSize) }
    }

    var glowSyllableBursts: Bool {
        didSet { defaults.set(glowSyllableBursts, forKey: Keys.glowSyllableBursts) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        soundSet = Self.stored(in: defaults, key: Keys.soundSet) ?? .synth8
        voiceVisual = Self.stored(in: defaults, key: Keys.voiceVisual) ?? .waveform
        waveformStyle = Self.stored(in: defaults, key: Keys.waveformStyle) ?? .chartLine
        revealStyle = Self.stored(in: defaults, key: Keys.revealStyle) ?? .slide
        longDraftStyle = Self.stored(in: defaults, key: Keys.longDraftStyle) ?? .growDown
        glowPalette = Self.stored(in: defaults, key: Keys.glowPalette) ?? .spectrum
        glowVoiceBrightness = Self.storedBool(
            in: defaults, key: Keys.glowVoiceBrightness, fallback: true
        )
        glowVoiceThickness = Self.storedBool(
            in: defaults, key: Keys.glowVoiceThickness, fallback: false
        )
        glowVoiceReach = Self.storedBool(
            in: defaults, key: Keys.glowVoiceReach, fallback: false
        )
        glowVoiceParticleCount = Self.storedBool(
            in: defaults, key: Keys.glowVoiceParticleCount, fallback: false
        )
        glowVoiceParticleSize = Self.storedBool(
            in: defaults, key: Keys.glowVoiceParticleSize, fallback: false
        )
        glowSyllableBursts = Self.storedBool(
            in: defaults, key: Keys.glowSyllableBursts, fallback: false
        )
    }

    private static func stored<Value: RawRepresentable<String>>(
        in defaults: UserDefaults,
        key: String
    ) -> Value? {
        defaults.string(forKey: key).flatMap { Value(rawValue: $0) }
    }

    /// Unlike `defaults.bool(forKey:)`, distinguishes "never set" so a lab
    /// knob can default to true.
    private static func storedBool(
        in defaults: UserDefaults,
        key: String,
        fallback: Bool
    ) -> Bool {
        defaults.object(forKey: key) as? Bool ?? fallback
    }
}
