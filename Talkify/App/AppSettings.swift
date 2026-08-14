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
    static let glowCenter = "hudGlowCenter"
    static let readAloudVoice = "readAloudVoice"
    static let dictationTriggerBinding = "dictationTriggerBinding"
    static let readAloudBinding = "readAloudBinding"
    static let recognitionLocale = "recognitionLocale"
    static let secondaryRecognitionLocale = "recognitionLocaleSecondary"
    static let secondaryTriggerBinding = "dictationTriggerBindingSecondary"
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

  var glowCenter: HUDGlowCenterStyle {
    didSet { defaults.set(glowCenter.rawValue, forKey: Keys.glowCenter) }
  }

  /// The Read Aloud voice's `AVSpeechSynthesisVoice` identifier; empty
  /// means the system default voice.
  var readAloudVoiceID: String {
    didSet { defaults.set(readAloudVoiceID, forKey: Keys.readAloudVoice) }
  }

  var dictationTriggerBinding: KeyBinding {
    didSet { Self.store(dictationTriggerBinding, in: defaults, key: Keys.dictationTriggerBinding) }
  }

  var readAloudBinding: KeyBinding {
    didSet { Self.store(readAloudBinding, in: defaults, key: Keys.readAloudBinding) }
  }

  /// The dictation language, as a locale identifier; empty means follow the
  /// Mac's own language, which is what every session did before the Language
  /// section existed.
  var recognitionLocaleIdentifier: String {
    didSet { defaults.set(recognitionLocaleIdentifier, forKey: Keys.recognitionLocale) }
  }

  /// The second language, with its own trigger key. Empty means off, which
  /// is the default: one key, one language, exactly as before.
  var secondaryRecognitionLocaleIdentifier: String {
    didSet {
      defaults.set(
        secondaryRecognitionLocaleIdentifier,
        forKey: Keys.secondaryRecognitionLocale
      )
    }
  }

  var secondaryTriggerBinding: KeyBinding {
    didSet { Self.store(secondaryTriggerBinding, in: defaults, key: Keys.secondaryTriggerBinding) }
  }

  /// True once a second language is chosen. The second trigger is ignored
  /// while this is false, so an unused binding cannot start a session.
  var isSecondLanguageEnabled: Bool {
    !secondaryRecognitionLocaleIdentifier.isEmpty
  }

  /// Transient, never persisted: true while a Shortcuts key recorder is
  /// armed, so global trigger handling pauses and the rebind keystroke
  /// cannot start a session.
  var isRecordingKeybind = false

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    soundSet = Self.stored(in: defaults, key: Keys.soundSet) ?? .synth8
    voiceVisual = Self.stored(in: defaults, key: Keys.voiceVisual) ?? .waveform
    waveformStyle = Self.stored(in: defaults, key: Keys.waveformStyle) ?? .chartLine
    revealStyle = Self.stored(in: defaults, key: Keys.revealStyle) ?? .slide
    longDraftStyle = Self.stored(in: defaults, key: Keys.longDraftStyle) ?? .growDown
    glowPalette = Self.stored(in: defaults, key: Keys.glowPalette) ?? .spectrum
    glowCenter = Self.stored(in: defaults, key: Keys.glowCenter) ?? .particles
    readAloudVoiceID = defaults.string(forKey: Keys.readAloudVoice) ?? ""
    dictationTriggerBinding = Self.storedBinding(
      in: defaults, key: Keys.dictationTriggerBinding
    ) ?? .fnTrigger
    readAloudBinding = Self.storedBinding(
      in: defaults, key: Keys.readAloudBinding
    ) ?? .optionEscape
    recognitionLocaleIdentifier = defaults.string(forKey: Keys.recognitionLocale) ?? ""
    secondaryRecognitionLocaleIdentifier =
      defaults.string(forKey: Keys.secondaryRecognitionLocale) ?? ""
    secondaryTriggerBinding = Self.storedBinding(
      in: defaults, key: Keys.secondaryTriggerBinding
    ) ?? .rightOptionTrigger
  }

  private static func stored<Value: RawRepresentable<String>>(
    in defaults: UserDefaults,
    key: String
  ) -> Value? {
    defaults.string(forKey: key).flatMap { Value(rawValue: $0) }
  }

  private static func storedBinding(in defaults: UserDefaults, key: String) -> KeyBinding? {
    defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(KeyBinding.self, from: $0) }
  }

  private static func store(_ binding: KeyBinding, in defaults: UserDefaults, key: String) {
    if let data = try? JSONEncoder().encode(binding) {
      defaults.set(data, forKey: key)
    }
  }
}

/// The preferences captured when Direct Dictation starts. A session keeps
/// this value until its end and paste sounds have played.
struct DictationSessionSettings: Equatable {
  let soundSet: DictationSoundSet
  let voiceVisual: HUDVoiceVisualStyle
  let waveformStyle: HUDWaveformStyle
  let revealStyle: HUDRevealStyle
  let longDraftStyle: HUDLongDraftStyle
  let glowPalette: HUDGlowPalette
  let glowCenter: HUDGlowCenterStyle

  @MainActor
  init(settings: AppSettings) {
    soundSet = settings.soundSet
    voiceVisual = settings.voiceVisual
    waveformStyle = settings.waveformStyle
    revealStyle = settings.revealStyle
    longDraftStyle = settings.longDraftStyle
    glowPalette = settings.glowPalette
    glowCenter = settings.glowCenter
  }
}

extension AppSettings {
  var sessionSettings: DictationSessionSettings {
    DictationSessionSettings(settings: self)
  }
}
