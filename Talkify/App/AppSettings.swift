import AppKit
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
    static let soundsEnabled = "dictationSoundsEnabled"
    static let soundVolume = "dictationSoundVolume"
    static let voiceVisual = "hudVoiceVisual"
    static let waveformStyle = "hudWaveformStyle"
    static let revealStyle = "hudRevealStyle"
    static let longDraftStyle = "hudLongDraftStyle"
    static let glowPalette = "hudGlowPalette"
    static let glowCenter = "hudGlowCenter"
    static let hudScale = "hudScale"
    static let readAloudVoice = "readAloudVoice"
    static let dictationTriggerBinding = "dictationTriggerBinding"
    static let readAloudBinding = "readAloudBinding"
    static let recognitionLocale = "recognitionLocale"
    static let secondaryRecognitionLocale = "recognitionLocaleSecondary"
    static let secondaryTriggerBinding = "dictationTriggerBindingSecondary"
    static let transcriptDestination = "transcriptDestination"
    static let transcriptFolder = "transcriptFolder"
  }

  @ObservationIgnored
  private let defaults: UserDefaults

  var soundSet: DictationSoundSet {
    didSet { defaults.set(soundSet.rawValue, forKey: Keys.soundSet) }
  }

  var dictationSoundsEnabled: Bool {
    didSet { defaults.set(dictationSoundsEnabled, forKey: Keys.soundsEnabled) }
  }

  private var storedDictationSoundVolume: Double

  var dictationSoundVolume: Double {
    get { storedDictationSoundVolume }
    set {
      storedDictationSoundVolume = DictationSoundSettings.normalizedVolume(newValue)
      defaults.set(storedDictationSoundVolume, forKey: Keys.soundVolume)
    }
  }

  /// Where a Drop Transcription writes its transcript. The chosen folder is
  /// kept even while the pick is `besideSource`, so switching back and forth
  /// does not lose it.
  var transcriptDestination: TranscriptDestination.Preference {
    didSet { defaults.set(transcriptDestination.rawValue, forKey: Keys.transcriptDestination) }
  }

  var transcriptFolder: URL? {
    didSet { defaults.set(transcriptFolder?.path(percentEncoded: false), forKey: Keys.transcriptFolder) }
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

  /// How large the HUD shape is, as a fraction of the standard size.
  /// `HUDMetrics` clamps it to its supported range; a stored value outside
  /// that range comes back clamped rather than refused.
  var hudScale: Double {
    didSet { defaults.set(hudScale, forKey: Keys.hudScale) }
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
    didSet {
      defaults.set(recognitionLocaleIdentifier, forKey: Keys.recognitionLocale)
      // Choosing the second language as the first leaves one language behind
      // two keys, so the second turns off rather than becoming a duplicate.
      if !recognitionLocaleIdentifier.isEmpty,
       recognitionLocaleIdentifier == secondaryRecognitionLocaleIdentifier {
        secondaryRecognitionLocaleIdentifier = ""
      }
    }
  }

  /// The second language, with its own trigger. Empty means off, which is the
  /// default: one trigger, one language, exactly as before.
  var secondaryRecognitionLocaleIdentifier: String {
    didSet {
      defaults.set(
        secondaryRecognitionLocaleIdentifier,
        forKey: Keys.secondaryRecognitionLocale
      )
      repairSecondaryTriggerConflictIfNeeded()
    }
  }

  var secondaryTriggerBinding: KeyBinding {
    didSet { Self.store(secondaryTriggerBinding, in: defaults, key: Keys.secondaryTriggerBinding) }
  }

  /// True once a second language is chosen. The second trigger is ignored
  /// while this is false, so an unused binding cannot start a session.
  /// The labels a split Drop Target shows, or empty when one language is
  /// configured and the target stays whole.
  var languageTagsForDrop: [String] {
    guard isSecondLanguageEnabled else { return [] }
    let primary = recognitionLocaleIdentifier.isEmpty
      ? Locale.current.identifier
      : recognitionLocaleIdentifier
    return [primary, secondaryRecognitionLocaleIdentifier]
      .map { SpeechLanguageCatalog.tag(for: Locale(identifier: $0)) }
  }

  /// Which language a drop chose. Index 1 is the second language and only
  /// exists while the target is split; anything else is the primary.
  func localeIdentifierForDrop(languageIndex: Int) -> String {
    guard languageIndex == 1, isSecondLanguageEnabled else {
      return recognitionLocaleIdentifier
    }
    return secondaryRecognitionLocaleIdentifier
  }

  var isSecondLanguageEnabled: Bool {
    !secondaryRecognitionLocaleIdentifier.isEmpty
  }

  /// Transient, never persisted: true while a Shortcuts input recorder is
  /// armed, so global trigger handling pauses and the rebind input cannot
  /// start a session.
  var isRecordingKeybind = false

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    soundSet = Self.stored(in: defaults, key: Keys.soundSet) ?? .synth8
    dictationSoundsEnabled = defaults.object(forKey: Keys.soundsEnabled) as? Bool ?? true
    let storedSoundVolume = defaults.object(forKey: Keys.soundVolume) as? Double ?? 0.5
    storedDictationSoundVolume = DictationSoundSettings.normalizedVolume(storedSoundVolume)
    transcriptDestination = Self.stored(in: defaults, key: Keys.transcriptDestination) ?? .besideSource
    transcriptFolder = (defaults.string(forKey: Keys.transcriptFolder)).map { URL(filePath: $0) }
    voiceVisual = Self.stored(in: defaults, key: Keys.voiceVisual) ?? .waveform
    waveformStyle = Self.stored(in: defaults, key: Keys.waveformStyle) ?? .chartLine
    revealStyle = Self.stored(in: defaults, key: Keys.revealStyle) ?? .slide
    longDraftStyle = Self.stored(in: defaults, key: Keys.longDraftStyle) ?? .growDown
    glowPalette = Self.stored(in: defaults, key: Keys.glowPalette) ?? .spectrum
    glowCenter = Self.stored(in: defaults, key: Keys.glowCenter) ?? .particles
    // `double(forKey:)` reads a missing key as zero, which would start every
    // existing user at the smallest HUD, so absence is checked directly.
    hudScale = defaults.object(forKey: Keys.hudScale) as? Double
      ?? Double(HUDMetrics.maximumScale)
    readAloudVoiceID = defaults.string(forKey: Keys.readAloudVoice) ?? ""
    dictationTriggerBinding = Self.storedBinding(
      in: defaults,
      key: Keys.dictationTriggerBinding,
      allowsMouseButton: true,
      allowsBareModifier: true
    ) ?? .fnTrigger
    readAloudBinding = Self.storedBinding(
      in: defaults,
      key: Keys.readAloudBinding,
      allowsMouseButton: false,
      allowsBareModifier: false
    ) ?? .optionEscape
    recognitionLocaleIdentifier = defaults.string(forKey: Keys.recognitionLocale) ?? ""
    secondaryRecognitionLocaleIdentifier =
      defaults.string(forKey: Keys.secondaryRecognitionLocale) ?? ""
    secondaryTriggerBinding = Self.storedBinding(
      in: defaults,
      key: Keys.secondaryTriggerBinding,
      allowsMouseButton: true,
      allowsBareModifier: true
    ) ?? .rightOptionTrigger
    repairSecondaryTriggerConflictIfNeeded()
  }

  private static func stored<Value: RawRepresentable<String>>(
    in defaults: UserDefaults,
    key: String
  ) -> Value? {
    defaults.string(forKey: key).flatMap { Value(rawValue: $0) }
  }

  private static func storedBinding(
    in defaults: UserDefaults,
    key: String,
    allowsMouseButton: Bool,
    allowsBareModifier: Bool
  ) -> KeyBinding? {
    guard let data = defaults.data(forKey: key),
       let binding = try? JSONDecoder().decode(KeyBinding.self, from: data),
       allowsMouseButton || !binding.isMouseButton,
       allowsBareModifier || !binding.isModifierKey
    else { return nil }
    return binding
  }

  private static func store(_ binding: KeyBinding, in defaults: UserDefaults, key: String) {
    if let data = try? JSONEncoder().encode(binding) {
      defaults.set(data, forKey: key)
    }
  }

  /// A disabled second language keeps its trigger preference. If another role
  /// takes that exact binding while it is off, enabling the language must not
  /// bring back a row whose trigger runtime silently drops as a duplicate.
  private func repairSecondaryTriggerConflictIfNeeded() {
    guard isSecondLanguageEnabled,
       secondaryTriggerBinding.hasSameInputAndModifiers(as: dictationTriggerBinding)
         || secondaryTriggerBinding.hasSameInputAndModifiers(as: readAloudBinding)
    else { return }

    let controlOption = KeyBinding(
      keyCode: 58,
      modifierFlags: CGEventFlags.maskControl.rawValue,
      isModifierKey: true,
      label: "⌃ ⌥",
      keyEquivalent: ""
    )
    let occupied = [dictationTriggerBinding, readAloudBinding]
    if let fallback = [
      KeyBinding.rightOptionTrigger,
      KeyBinding.fnTrigger,
      controlOption,
    ].first { candidate in
      !occupied.contains { $0.hasSameInputAndModifiers(as: candidate) }
    } {
      secondaryTriggerBinding = fallback
    }
  }
}

/// The preferences captured when Direct Dictation starts. A session keeps
/// this value until its end and paste sounds have played.
struct DictationSessionSettings: Equatable {
  let sounds: DictationSoundSettings
  let voiceVisual: HUDVoiceVisualStyle
  let waveformStyle: HUDWaveformStyle
  let revealStyle: HUDRevealStyle
  let longDraftStyle: HUDLongDraftStyle
  let glowPalette: HUDGlowPalette
  let glowCenter: HUDGlowCenterStyle
  let hudMetrics: HUDMetrics

  /// The colour a Drop Transcription wears — on the HUD's target and card, and
  /// on the status ghost while a file job fills it. Edge Glow lends its
  /// palette's own hue; every other visual keeps Talkify blue. One definition,
  /// so the shape and the menu bar can never drift apart (CONTEXT.md).
  var dropAccent: NSColor {
    voiceVisual == .glow ? glowPalette.statusAccent : SettingsTheme.accentColor
  }

  @MainActor
  init(settings: AppSettings) {
    sounds = DictationSoundSettings(
      set: settings.soundSet,
      isEnabled: settings.dictationSoundsEnabled,
      volume: settings.dictationSoundVolume
    )
    voiceVisual = settings.voiceVisual
    waveformStyle = settings.waveformStyle
    revealStyle = settings.revealStyle
    longDraftStyle = settings.longDraftStyle
    glowPalette = settings.glowPalette
    glowCenter = settings.glowCenter
    hudMetrics = HUDMetrics(scale: CGFloat(settings.hudScale))
  }
}

extension AppSettings {
  var sessionSettings: DictationSessionSettings {
    DictationSessionSettings(settings: self)
  }
}
