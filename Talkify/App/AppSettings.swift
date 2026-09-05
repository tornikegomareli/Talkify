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
    static let duckOtherAudio = "duckOtherAudioWhileDictating"
    static let soundVolume = "dictationSoundVolume"
    static let voiceVisual = "hudVoiceVisual"
    static let waveformStyle = "hudWaveformStyle"
    static let revealStyle = "hudRevealStyle"
    static let longDraftStyle = "hudLongDraftStyle"
    static let glowPalette = "hudGlowPalette"
    static let glowCenter = "hudGlowCenter"
    static let hudScale = "hudScale"
    static let readAloudVoice = "readAloudVoice"
    static let readAloudTranslates = "readAloudTranslates"
    static let dictationTriggerBinding = "dictationTriggerBinding"
    static let readAloudBinding = "readAloudBinding"
    static let recognitionLocale = "recognitionLocale"
    static let secondaryRecognitionLocale = "recognitionLocaleSecondary"
    static let secondaryTriggerBinding = "dictationTriggerBindingSecondary"
    static let translateTriggerBinding = "dictationTriggerBindingTranslate"
    static let translationTarget = "translationTargetLanguage"
    static let transcriptDestination = "transcriptDestination"
    static let transcriptFolder = "transcriptFolder"
    static let insertionDestination = "dictationInsertionDestination"
    static let hudClearsMenuBar = "hudClearsMenuBar"
    static let historyEnabled = "dictationHistoryEnabled"
    static let historyFolder = "dictationHistoryFolder"
    static let promptShapingEnabled = "dictationPromptShapingEnabled"
    static let promptShapingPrompt = "dictationPromptShapingPrompt"
    static let shapingPrompts = "dictationShapingPrompts"
  }

  @ObservationIgnored
  private let defaults: UserDefaults

  var soundSet: DictationSoundSet {
    didSet { defaults.set(soundSet.rawValue, forKey: Keys.soundSet) }
  }

  /// Lowers the system output while a session listens. Off by default: it
  /// moves a system-wide control, which is not something to start doing to
  /// someone who did not ask for it.
  var duckOtherAudioWhileDictating: Bool {
    didSet { defaults.set(duckOtherAudioWhileDictating, forKey: Keys.duckOtherAudio) }
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

  /// Where a finished Direct Dictation session's text goes: the paste that
  /// always happened, the clipboard alone, or both.
  var insertionDestination: InsertionDestination {
    didSet { defaults.set(insertionDestination.rawValue, forKey: Keys.insertionDestination) }
  }

  /// Whether finished dictation text is saved to the history folder. Off by
  /// default: persisting no recognized text is the standing privacy stance,
  /// and only the user turns this on.
  var dictationHistoryEnabled: Bool {
    didSet { defaults.set(dictationHistoryEnabled, forKey: Keys.historyEnabled) }
  }

  /// The history folder, kept even while history is off so turning it back
  /// on returns to the same place. Nil means the default `~/Documents/Talkify/`.
  var dictationHistoryFolder: URL? {
    didSet { defaults.set(dictationHistoryFolder?.path(percentEncoded: false), forKey: Keys.historyFolder) }
  }

  /// The folder history writes to right now: the user's pick, or the default.
  var resolvedHistoryFolder: URL {
    dictationHistoryFolder ?? DictationHistoryStore.defaultFolderURL
  }

  /// Whether the beta prompt shaping pass runs on finished dictation text.
  /// Off by default: the default session inserts raw finalized text exactly
  /// as it always has.
  var promptShapingEnabled: Bool {
    didSet { defaults.set(promptShapingEnabled, forKey: Keys.promptShapingEnabled) }
  }

  /// The selected shaping prompt's id, kept even while shaping is off.
  var promptShapingPromptID: String {
    didSet { defaults.set(promptShapingPromptID, forKey: Keys.promptShapingPrompt) }
  }

  /// The user-editable shaping prompt library, stored whole as JSON. A
  /// missing or unreadable value reseeds from the built-in defaults rather
  /// than presenting an empty library.
  var shapingPrompts: [ShapingPrompt] {
    didSet {
      if let data = try? JSONEncoder().encode(shapingPrompts) {
        defaults.set(data, forKey: Keys.shapingPrompts)
      }
    }
  }

  /// Puts the seed prompts back. The selection is left alone on purpose: a
  /// selected id the seeds do not carry resolves to nil, which already
  /// inserts the raw words unchanged.
  func restoreDefaultShapingPrompts() {
    shapingPrompts = ShapingPrompt.defaults
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
  /// Whether Read Aloud translates a selection into the voice's own language
  /// before speaking it. Off by default: Read Aloud has always read what was
  /// written, and translating without being asked would change what a shortcut
  /// someone already uses does.
  var readAloudTranslates: Bool {
    didSet { defaults.set(readAloudTranslates, forKey: Keys.readAloudTranslates) }
  }

  /// Whether the shape hangs below the menu bar on a display with no notch.
  ///
  /// Off, so it sits where the notch would be and looks like the housing it
  /// imitates. On for a crowded menu bar, where a centred 540-point shape can
  /// reach far enough right to cover a status item — including Talkify's own,
  /// which is how a session is stopped without the key (issue #83).
  var hudClearsMenuBar: Bool {
    didSet { defaults.set(hudClearsMenuBar, forKey: Keys.hudClearsMenuBar) }
  }

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
    }
  }

  var secondaryTriggerBinding: KeyBinding {
    didSet { Self.store(secondaryTriggerBinding, in: defaults, key: Keys.secondaryTriggerBinding) }
  }

  /// The trigger that dictates in the primary language and inserts a
  /// translation. Defaults to right command, which shares no key with fn:
  /// any fn combination would end a held plain session the moment its
  /// modifier arrived, because fn alone is already a trigger.
  var translateTriggerBinding: KeyBinding {
    didSet { Self.store(translateTriggerBinding, in: defaults, key: Keys.translateTriggerBinding) }
  }

  /// The language Dictate and Translate translates into, as a language code.
  /// Empty means off, which is the default: the trigger is not installed at
  /// all until a target is chosen, so an unconfigured key swallows nothing.
  var translationTargetIdentifier: String {
    didSet { defaults.set(translationTargetIdentifier, forKey: Keys.translationTarget) }
  }

  var isTranslationEnabled: Bool {
    !translationTargetIdentifier.isEmpty
  }

  /// The pair a session would translate, or nil when translation is off or
  /// would translate a language into itself.
  func translationPair(from source: Locale) -> TranslationPair? {
    guard isTranslationEnabled else { return nil }
    let target = Locale.Language(identifier: translationTargetIdentifier)
    guard let sourceCode = source.language.languageCode?.identifier,
       let targetCode = target.languageCode?.identifier,
       sourceCode != targetCode
    else {
      return nil
    }
    return TranslationPair(source: source.language, target: target)
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
    duckOtherAudioWhileDictating = defaults.object(forKey: Keys.duckOtherAudio) as? Bool ?? false
    let storedSoundVolume = defaults.object(forKey: Keys.soundVolume) as? Double ?? 0.5
    storedDictationSoundVolume = DictationSoundSettings.normalizedVolume(storedSoundVolume)
    transcriptDestination = Self.stored(in: defaults, key: Keys.transcriptDestination) ?? .besideSource
    transcriptFolder = (defaults.string(forKey: Keys.transcriptFolder)).map { URL(filePath: $0) }
    insertionDestination = Self.stored(in: defaults, key: Keys.insertionDestination) ?? .insert
    dictationHistoryEnabled = defaults.object(forKey: Keys.historyEnabled) as? Bool ?? false
    dictationHistoryFolder = (defaults.string(forKey: Keys.historyFolder)).map { URL(filePath: $0) }
    promptShapingEnabled = defaults.object(forKey: Keys.promptShapingEnabled) as? Bool ?? false
    promptShapingPromptID = defaults.string(forKey: Keys.promptShapingPrompt)
      ?? ShapingPrompt.defaults[0].id
    shapingPrompts = Self.storedShapingPrompts(in: defaults) ?? ShapingPrompt.defaults
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
    hudClearsMenuBar = defaults.bool(forKey: Keys.hudClearsMenuBar)
    readAloudVoiceID = defaults.string(forKey: Keys.readAloudVoice) ?? ""
    readAloudTranslates = defaults.bool(forKey: Keys.readAloudTranslates)
    dictationTriggerBinding = Self.storedBinding(
      in: defaults,
      key: Keys.dictationTriggerBinding,
      allowsMouseButton: true
    ) ?? .fnTrigger
    readAloudBinding = Self.storedBinding(
      in: defaults,
      key: Keys.readAloudBinding,
      allowsMouseButton: false
    ) ?? .optionEscape
    recognitionLocaleIdentifier = defaults.string(forKey: Keys.recognitionLocale) ?? ""
    secondaryRecognitionLocaleIdentifier =
      defaults.string(forKey: Keys.secondaryRecognitionLocale) ?? ""
    secondaryTriggerBinding = Self.storedBinding(
      in: defaults,
      key: Keys.secondaryTriggerBinding,
      allowsMouseButton: true
    ) ?? .rightOptionTrigger
    translateTriggerBinding = Self.storedBinding(
      in: defaults,
      key: Keys.translateTriggerBinding,
      allowsMouseButton: true
    ) ?? .rightCommandTrigger
    translationTargetIdentifier = defaults.string(forKey: Keys.translationTarget) ?? ""
  }

  private static func stored<Value: RawRepresentable<String>>(
    in defaults: UserDefaults,
    key: String
  ) -> Value? {
    defaults.string(forKey: key).flatMap { Value(rawValue: $0) }
  }

  /// `allowsMouseButton` is false for Read Aloud, which fires from keyDown
  /// and so has no mouse path at all: a stored mouse binding there could only
  /// ever be dead.
  private static func storedBinding(
    in defaults: UserDefaults,
    key: String,
    allowsMouseButton: Bool
  ) -> KeyBinding? {
    guard let data = defaults.data(forKey: key),
       let binding = try? JSONDecoder().decode(KeyBinding.self, from: data),
       allowsMouseButton || !binding.isMouseButton
    else { return nil }
    return binding
  }

  private static func storedShapingPrompts(in defaults: UserDefaults) -> [ShapingPrompt]? {
    guard let data = defaults.data(forKey: Keys.shapingPrompts),
       let prompts = try? JSONDecoder().decode([ShapingPrompt].self, from: data)
    else { return nil }
    return prompts
  }

  private static func store(_ binding: KeyBinding, in defaults: UserDefaults, key: String) {
    if let data = try? JSONEncoder().encode(binding) {
      defaults.set(data, forKey: key)
    }
  }

  func binding(for role: BindingRole) -> KeyBinding {
    switch role {
    case .dictation: dictationTriggerBinding
    case .secondLanguage: secondaryTriggerBinding
    case .translate: translateTriggerBinding
    case .readAloud: readAloudBinding
    }
  }

  func setBinding(_ binding: KeyBinding, for role: BindingRole) {
    switch role {
    case .dictation: dictationTriggerBinding = binding
    case .secondLanguage: secondaryTriggerBinding = binding
    case .translate: translateTriggerBinding = binding
    case .readAloud: readAloudBinding = binding
    }
  }

  /// The role already using this exact input and modifiers, if any.
  ///
  /// One rule in one place: the recorders, the Language section and
  /// `setBindings` would otherwise each decide for themselves what clashes.
  /// A second language that is off holds no binding, so it clashes with
  /// nothing. Only the input matters — the same binding recorded and clicked
  /// carries a different label, and comparing whole values would miss it.
  func roleUsing(_ candidate: KeyBinding, excluding role: BindingRole) -> BindingRole? {
    BindingRole.allCases.first { other in
      guard other != role else { return false }
      guard other != .secondLanguage || isSecondLanguageEnabled else { return false }
      // A translate trigger that has no target holds no binding, so an
      // unconfigured one must not report a clash with a real binding.
      guard other != .translate || isTranslationEnabled else { return false }
      return binding(for: other).hasSameInputAndModifiers(as: candidate)
    }
  }
}

/// Which recorded binding is being talked about. Shared so the Shortcuts
/// section, the Language section and the event tap all name the same three
/// roles.
enum BindingRole: Hashable, CaseIterable {
  case dictation
  case secondLanguage
  case translate
  case readAloud

  var title: String {
    switch self {
    case .dictation: "Direct Dictation"
    case .secondLanguage: "Second Language"
    case .translate: "Translate"
    case .readAloud: "Read Aloud"
    }
  }
}

/// The preferences captured when Direct Dictation starts. A session keeps
/// this value until its end and paste sounds have played.
struct DictationSessionSettings: Equatable {
  let sounds: DictationSoundSettings
  let insertionDestination: InsertionDestination
  /// The translation this session performs, or nil when it inserts the words
  /// as spoken. Captured with everything else: changing the target
  /// mid-session must not redirect the session already under way (ADR-0004).
  let translation: TranslationPair?
  let historyEnabled: Bool
  let historyFolder: URL
  /// Captured with everything else: a session that started while ducking was
  /// on has to restore the volume even if the toggle flips mid-session.
  let ducksOtherAudio: Bool
  /// The shaping prompt this session applies, or nil while shaping is off
  /// or the stored id names nothing in the user's prompt list.
  let shapingPrompt: ShapingPrompt?
  /// The whole prompt library while shaping is on, empty while it is off, so
  /// the arrow keys can cycle the session's pick without reading a library
  /// that may change mid-session.
  let shapingLibrary: [ShapingPrompt]
  let voiceVisual: HUDVoiceVisualStyle
  let waveformStyle: HUDWaveformStyle
  let revealStyle: HUDRevealStyle
  let longDraftStyle: HUDLongDraftStyle
  let glowPalette: HUDGlowPalette
  let glowCenter: HUDGlowCenterStyle
  let hudMetrics: HUDMetrics

  /// The colour a Drop Transcription wears — on the HUD's target and card, and
  /// on the status ghost while a file job fills it. Edge Glow and Edge Glow +
  /// Draft lend the palette's own hue; every other visual keeps Talkify blue.
  /// One definition, so the shape and the menu bar can never drift apart
  /// (CONTEXT.md).
  var dropAccent: NSColor {
    voiceVisual.usesEdgeGlow ? glowPalette.statusAccent : SettingsTheme.accentColor
  }

  @MainActor
  init(settings: AppSettings, translation: TranslationPair? = nil) {
    self.translation = translation
    sounds = DictationSoundSettings(
      set: settings.soundSet,
      isEnabled: settings.dictationSoundsEnabled,
      volume: settings.dictationSoundVolume
    )
    insertionDestination = settings.insertionDestination
    historyEnabled = settings.dictationHistoryEnabled
    historyFolder = settings.resolvedHistoryFolder
    ducksOtherAudio = settings.duckOtherAudioWhileDictating
    shapingPrompt = settings.promptShapingEnabled
      ? settings.shapingPrompts.prompt(for: settings.promptShapingPromptID)
      : nil
    shapingLibrary = settings.promptShapingEnabled ? settings.shapingPrompts : []
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
