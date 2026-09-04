import Foundation
import Testing
@testable import Talkify

@MainActor
struct AppSettingsTests {
  private func freshDefaults() -> UserDefaults {
    let name = "AppSettingsTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
  }

  @Test func emptyStoreYieldsDefaults() {
    let settings = AppSettings(defaults: freshDefaults())
    #expect(settings.soundSet == .synth8)
    #expect(settings.dictationSoundsEnabled)
    #expect(settings.dictationSoundVolume == 0.5)
    #expect(settings.voiceVisual == .waveform)
    #expect(settings.waveformStyle == .chartLine)
    #expect(settings.revealStyle == .slide)
    #expect(settings.longDraftStyle == .growDown)
    // Existing users must not be resized by an upgrade.
    #expect(settings.hudScale == Double(HUDMetrics.maximumScale))
    #expect(settings.readAloudVoiceID.isEmpty)
    #expect(settings.dictationTriggerBinding == .fnTrigger)
    #expect(settings.readAloudBinding == .optionEscape)
  }

  @Test func everyPreferenceRoundTrips() {
    let defaults = freshDefaults()
    let settings = AppSettings(defaults: defaults)
    settings.soundSet = .chime
    settings.dictationSoundsEnabled = false
    settings.dictationSoundVolume = 0.25
    settings.voiceVisual = .glow
    settings.waveformStyle = .dots
    settings.revealStyle = .bloom
    settings.longDraftStyle = .shrinkToFit
    settings.hudScale = 0.75
    settings.readAloudVoiceID = "com.apple.voice.premium.en-US.Zoe"
    let f5Binding = KeyBinding(
      keyCode: 96, modifierFlags: 0, isModifierKey: false,
      label: "F5", keyEquivalent: ""
    )
    let rightCommandTrigger = KeyBinding(
      keyCode: 54, modifierFlags: 0, isModifierKey: true,
      label: "right ⌘", keyEquivalent: ""
    )
    settings.dictationTriggerBinding = rightCommandTrigger
    settings.readAloudBinding = f5Binding

    let reloaded = AppSettings(defaults: defaults)
    #expect(reloaded.soundSet == .chime)
    #expect(!reloaded.dictationSoundsEnabled)
    #expect(reloaded.dictationSoundVolume == 0.25)
    #expect(reloaded.voiceVisual == .glow)
    #expect(reloaded.waveformStyle == .dots)
    #expect(reloaded.revealStyle == .bloom)
    #expect(reloaded.longDraftStyle == .shrinkToFit)
    #expect(reloaded.hudScale == 0.75)
    #expect(reloaded.readAloudVoiceID == "com.apple.voice.premium.en-US.Zoe")
    #expect(reloaded.dictationTriggerBinding == rightCommandTrigger)
    #expect(reloaded.readAloudBinding == f5Binding)
  }

  @Test func preferencesUseStableStorageKeys() {
    let defaults = freshDefaults()
    let settings = AppSettings(defaults: defaults)
    settings.soundSet = .click
    settings.dictationSoundsEnabled = false
    settings.dictationSoundVolume = 0.2
    settings.voiceVisual = .glow
    settings.waveformStyle = .silver
    settings.revealStyle = .drift
    settings.longDraftStyle = .tailOnly
    settings.readAloudVoiceID = "com.apple.voice.enhanced.en-GB.Jamie"

    #expect(defaults.string(forKey: "dictationSoundSet") == "Click")
    #expect(defaults.object(forKey: "dictationSoundsEnabled") as? Bool == false)
    #expect(defaults.double(forKey: "dictationSoundVolume") == 0.2)
    #expect(defaults.string(forKey: "hudVoiceVisual") == "Edge Glow")
    settings.voiceVisual = .waveDraft
    #expect(defaults.string(forKey: "hudVoiceVisual") == "Waveform + Draft")
    #expect(defaults.string(forKey: "hudWaveformStyle") == "Silver")
    #expect(defaults.string(forKey: "hudRevealStyle") == "Drift")
    #expect(defaults.string(forKey: "hudLongDraftStyle") == "Tail Only")
    #expect(defaults.string(forKey: "readAloudVoice") == "com.apple.voice.enhanced.en-GB.Jamie")
  }

  @Test func keyBindingsPersistUnderTheirHistoricalKeys() {
    let defaults = freshDefaults()
    let settings = AppSettings(defaults: defaults)
    settings.dictationTriggerBinding = .fnTrigger
    settings.readAloudBinding = .optionEscape

    #expect(defaults.data(forKey: "dictationTriggerBinding") != nil)
    #expect(defaults.data(forKey: "readAloudBinding") != nil)
  }

  @Test func mouseTriggerRoundTripsUnderTheHistoricalBindingKey() throws {
    let defaults = freshDefaults()
    let settings = AppSettings(defaults: defaults)
    let middleClick = try #require(KeyBinding.mouseButton(number: 2))

    settings.dictationTriggerBinding = middleClick

    let reloaded = AppSettings(defaults: defaults)
    #expect(reloaded.dictationTriggerBinding == middleClick)
    #expect(defaults.data(forKey: "dictationTriggerBinding") != nil)
  }

  @Test func historicalKeyboardBindingDecodesWithoutAMouseField() throws {
    let json = """
      {
        "keyCode": 63,
        "modifierFlags": 0,
        "isModifierKey": true,
        "label": "fn",
        "keyEquivalent": ""
      }
      """

    let binding = try JSONDecoder().decode(KeyBinding.self, from: Data(json.utf8))
    #expect(binding == .fnTrigger)
    #expect(!binding.isMouseButton)
  }

  @Test func readAloudRejectsAStoredMouseBinding() throws {
    let defaults = freshDefaults()
    let middleClick = try #require(KeyBinding.mouseButton(number: 2))
    defaults.set(
      try JSONEncoder().encode(middleClick),
      forKey: "readAloudBinding"
    )

    let settings = AppSettings(defaults: defaults)
    #expect(settings.readAloudBinding == .optionEscape)
  }

  /// The label is captured at record time, so the same binding recorded and
  /// clicked are not equal values. A clash is about the input, not the label.
  @Test func aClashIsFoundByInputRatherThanByLabel() throws {
    let settings = AppSettings(defaults: freshDefaults())
    let middleClick = try #require(KeyBinding.mouseButton(number: 2))
    var relabelled = middleClick
    relabelled.label = "Wheel"
    settings.dictationTriggerBinding = middleClick
    settings.secondaryRecognitionLocaleIdentifier = "de_DE"

    #expect(settings.roleUsing(relabelled, excluding: .secondLanguage) == .dictation)
    #expect(settings.roleUsing(middleClick, excluding: .dictation) == nil)
  }

  /// A second language that is off holds no binding, so nothing clashes with
  /// it — and turning it back on says so on the row rather than rewriting the
  /// trigger the user picked.
  @Test func anOffSecondLanguageClashesWithNothingAndKeepsItsTrigger() throws {
    let settings = AppSettings(defaults: freshDefaults())
    let middleClick = try #require(KeyBinding.mouseButton(number: 2))
    settings.secondaryRecognitionLocaleIdentifier = "de_DE"
    settings.secondaryTriggerBinding = middleClick
    settings.secondaryRecognitionLocaleIdentifier = ""

    #expect(settings.roleUsing(middleClick, excluding: .dictation) == nil)

    settings.dictationTriggerBinding = middleClick
    settings.secondaryRecognitionLocaleIdentifier = "de_DE"

    #expect(settings.secondaryTriggerBinding == middleClick)
    #expect(settings.roleUsing(middleClick, excluding: .secondLanguage) == .dictation)
  }

  @Test func theTranslateBindingDefaultsToRightCommandAndRoundTrips() throws {
    let defaults = freshDefaults()
    #expect(AppSettings(defaults: defaults).translateTriggerBinding == .rightCommandTrigger)

    let settings = AppSettings(defaults: defaults)
    settings.translateTriggerBinding = .optionEscape
    #expect(AppSettings(defaults: defaults).translateTriggerBinding == .optionEscape)
  }

  /// Off by default, and the trigger is not installed until a target exists,
  /// so an unconfigured key behaves as if the feature were not there.
  @Test func translationIsOffUntilATargetIsChosen() {
    let settings = AppSettings(defaults: freshDefaults())
    #expect(settings.translationTargetIdentifier == "")
    #expect(!settings.isTranslationEnabled)

    settings.translationTargetIdentifier = "es"
    #expect(settings.isTranslationEnabled)
  }

  /// An unconfigured translate binding holds nothing, so it must not report a
  /// clash with a binding somebody is actually using.
  @Test func anUnconfiguredTranslateBindingClashesWithNothing() {
    let settings = AppSettings(defaults: freshDefaults())
    settings.translateTriggerBinding = .fnTrigger

    #expect(settings.roleUsing(.fnTrigger, excluding: .dictation) == nil)

    settings.translationTargetIdentifier = "es"
    #expect(settings.roleUsing(.fnTrigger, excluding: .dictation) == .translate)
  }

  /// Translating a language into itself is not a translation, so the pair is
  /// dropped rather than sending text through a translator to be unchanged.
  @Test func aTargetEqualToTheSourceIsNotAPair() {
    let settings = AppSettings(defaults: freshDefaults())
    settings.translationTargetIdentifier = "en"

    #expect(settings.translationPair(from: Locale(identifier: "en_US")) == nil)
    #expect(settings.translationPair(from: Locale(identifier: "de_DE")) != nil)
    #expect(settings.translationPair(from: Locale(identifier: "de_DE"))?.tag == "DE → EN")
  }

  @Test func noTargetMeansNoPair() {
    let settings = AppSettings(defaults: freshDefaults())
    #expect(settings.translationPair(from: Locale(identifier: "en_US")) == nil)
  }

  @Test func languagesDefaultToOneFollowingTheMac() {
    let settings = AppSettings(defaults: freshDefaults())
    #expect(settings.recognitionLocaleIdentifier == "")
    #expect(settings.secondaryRecognitionLocaleIdentifier == "")
    #expect(!settings.isSecondLanguageEnabled)
    #expect(settings.secondaryTriggerBinding == .rightOptionTrigger)
  }

  @Test func secondLanguageTurnsOnWithItsPickAndOffAgain() {
    let defaults = freshDefaults()
    let settings = AppSettings(defaults: defaults)

    settings.recognitionLocaleIdentifier = "en_US"
    settings.secondaryRecognitionLocaleIdentifier = "de_DE"
    #expect(settings.isSecondLanguageEnabled)
    #expect(defaults.string(forKey: "recognitionLocale") == "en_US")
    #expect(defaults.string(forKey: "recognitionLocaleSecondary") == "de_DE")

    settings.secondaryRecognitionLocaleIdentifier = ""
    #expect(!settings.isSecondLanguageEnabled)
  }

  @Test func languagePicksSurviveARelaunch() {
    let defaults = freshDefaults()
    let first = AppSettings(defaults: defaults)
    let customTrigger = KeyBinding(
      keyCode: 96,
      modifierFlags: 0,
      isModifierKey: false,
      label: "F5",
      keyEquivalent: ""
    )
    first.recognitionLocaleIdentifier = "fr_FR"
    first.secondaryRecognitionLocaleIdentifier = "it_IT"
    first.secondaryTriggerBinding = customTrigger

    let second = AppSettings(defaults: defaults)
    #expect(second.recognitionLocaleIdentifier == "fr_FR")
    #expect(second.secondaryRecognitionLocaleIdentifier == "it_IT")
    #expect(second.secondaryTriggerBinding == customTrigger)
  }

  @Test func downloadsAppearWhileRunningAndClearWhenDone() {
    let state = SettingsRuntimeState()
    #expect(state.languageDownloads.isEmpty)

    state.setDownload(identifier: "de_DE", fraction: 0.4)
    #expect(state.languageDownloads["de_DE"] == 0.4)

    state.setDownload(identifier: "de_DE", fraction: nil)
    #expect(state.languageDownloads.isEmpty)
  }

  /// The name is localized for whoever is reading it, so the expectation comes
  /// from the same source rather than hardcoding English. What the test pins is
  /// the behaviour: the region is dropped, and both German regions read alike.
  @Test func languagesAreNamedWithoutTheirRegionForProse() {
    let expected = Locale.current.localizedString(forLanguageCode: "de")?.localizedCapitalized
    let germany = SpeechLanguageCatalog.shortName(for: Locale(identifier: "de_DE"))
    let switzerland = SpeechLanguageCatalog.shortName(for: Locale(identifier: "de_CH"))

    #expect(germany == switzerland)
    #expect(!germany.contains("_"))
    if let expected {
      #expect(germany == expected)
    }
  }

  @Test func pickingTheSecondLanguageAsTheFirstTurnsTheSecondOff() {
    let settings = AppSettings(defaults: freshDefaults())
    settings.recognitionLocaleIdentifier = "en_US"
    settings.secondaryRecognitionLocaleIdentifier = "de_DE"
    #expect(settings.isSecondLanguageEnabled)

    settings.recognitionLocaleIdentifier = "de_DE"
    #expect(!settings.isSecondLanguageEnabled)
    #expect(settings.secondaryRecognitionLocaleIdentifier == "")
  }

  /// The tag is the language code, uppercased, however long the code is.
  ///
  /// This used to truncate to two characters, which gave Cantonese the tag
  /// "YU" sitting beside Chinese as "ZH". Truncation was never the rule worth
  /// keeping; the rule is that the tag names the language.
  @Test func languageTagsAreTheUppercasedLanguageCode() {
    #expect(SpeechLanguageCatalog.tag(for: Locale(identifier: "de_DE")) == "DE")
    #expect(SpeechLanguageCatalog.tag(for: Locale(identifier: "en_US")) == "EN")
    #expect(SpeechLanguageCatalog.tag(for: Locale(identifier: "yue_CN")) == "YUE")
  }

  @Test func unknownStoredValueFallsBackToDefault() {
    let defaults = freshDefaults()
    defaults.set("Kazoo", forKey: "dictationSoundSet")
    defaults.set("Sparkles", forKey: "hudVoiceVisual")

    let settings = AppSettings(defaults: defaults)
    #expect(settings.soundSet == .synth8)
    #expect(settings.voiceVisual == .waveform)
  }

  @Test func sessionSnapshotDoesNotChangeWithStoredSettings() {
    let settings = AppSettings(defaults: freshDefaults())
    let snapshot = settings.sessionSettings

    settings.soundSet = .chime
    settings.voiceVisual = .glow
    settings.waveformStyle = .dots
    settings.revealStyle = .bloom
    settings.longDraftStyle = .tailOnly
    settings.glowPalette = .aurora
    settings.glowCenter = .siriOrb
    settings.hudScale = 0.6

    #expect(snapshot.sounds.set == .synth8)
    #expect(snapshot.voiceVisual == .waveform)
    #expect(snapshot.waveformStyle == .chartLine)
    #expect(snapshot.revealStyle == .slide)
    #expect(snapshot.longDraftStyle == .growDown)
    #expect(snapshot.glowPalette == .spectrum)
    #expect(snapshot.glowCenter == .particles)
    #expect(snapshot.hudMetrics == .standard)
  }

  @Test func sessionSnapshotCapturesSoundPreferences() {
    let settings = AppSettings(defaults: freshDefaults())
    settings.soundSet = .chime
    settings.dictationSoundsEnabled = false
    settings.dictationSoundVolume = 0.25

    let snapshot = settings.sessionSettings
    settings.soundSet = .click
    settings.dictationSoundsEnabled = true
    settings.dictationSoundVolume = 0.75

    #expect(snapshot.sounds.set == .chime)
    #expect(!snapshot.sounds.isEnabled)
    #expect(snapshot.sounds.volume == 0.25)
  }

  @Test func insertionDestinationDefaultsToInsertAndRoundTrips() {
    let defaults = freshDefaults()
    let settings = AppSettings(defaults: defaults)
    #expect(settings.insertionDestination == .insert)

    settings.insertionDestination = .both
    #expect(defaults.string(forKey: "dictationInsertionDestination") == "both")

    let reloaded = AppSettings(defaults: defaults)
    #expect(reloaded.insertionDestination == .both)
  }

  @Test func historyDefaultsToOffWithTheDocumentsFolder() {
    let settings = AppSettings(defaults: freshDefaults())
    #expect(!settings.dictationHistoryEnabled)
    #expect(settings.dictationHistoryFolder == nil)
    #expect(settings.resolvedHistoryFolder == DictationHistoryStore.defaultFolderURL)
  }

  @Test func historyPreferencesRoundTripUnderTheirKeys() {
    let defaults = freshDefaults()
    let settings = AppSettings(defaults: defaults)
    settings.dictationHistoryEnabled = true
    settings.dictationHistoryFolder = URL(filePath: "/tmp/history")

    #expect(defaults.object(forKey: "dictationHistoryEnabled") as? Bool == true)
    #expect(defaults.string(forKey: "dictationHistoryFolder") == "/tmp/history")

    let reloaded = AppSettings(defaults: defaults)
    #expect(reloaded.dictationHistoryEnabled)
    #expect(reloaded.dictationHistoryFolder?.path(percentEncoded: false) == "/tmp/history")
  }

  @Test func sessionSnapshotCapturesTheHistoryChoice() {
    let settings = AppSettings(defaults: freshDefaults())
    settings.dictationHistoryEnabled = true
    settings.dictationHistoryFolder = URL(filePath: "/tmp/history")

    let snapshot = settings.sessionSettings
    settings.dictationHistoryEnabled = false
    settings.dictationHistoryFolder = nil

    #expect(snapshot.historyEnabled)
    #expect(snapshot.historyFolder.path(percentEncoded: false) == "/tmp/history")
  }

  @Test func promptShapingDefaultsToOffWithTheFirstPrompt() {
    let settings = AppSettings(defaults: freshDefaults())
    #expect(!settings.promptShapingEnabled)
    #expect(settings.promptShapingPromptID == ShapingPrompt.defaults[0].id)
  }

  @Test func freshStoreSeedsTheBuiltInShapingPrompts() {
    let settings = AppSettings(defaults: freshDefaults())
    #expect(settings.shapingPrompts == ShapingPrompt.defaults)
  }

  @Test func editedShapingPromptsPersistAndReadBack() {
    let defaults = freshDefaults()
    let settings = AppSettings(defaults: defaults)
    settings.shapingPrompts[0].name = "My grammar fixer"
    settings.shapingPrompts.append(ShapingPrompt(
      id: "mine",
      name: "Mine",
      preInstruction: "Shout it.",
      postInstruction: "Politely.",
      exampleInput: "",
      exampleOutput: ""
    ))
    settings.shapingPrompts.removeAll { $0.id == "bullet-lists" }

    let reloaded = AppSettings(defaults: defaults)
    #expect(reloaded.shapingPrompts == settings.shapingPrompts)
    #expect(reloaded.shapingPrompts[0].name == "My grammar fixer")
    #expect(reloaded.shapingPrompts.prompt(for: "mine")?.postInstruction == "Politely.")
    #expect(reloaded.shapingPrompts.prompt(for: "bullet-lists") == nil)
  }

  @Test func undecodableStoredShapingPromptsReseedFromTheDefaults() {
    let defaults = freshDefaults()
    defaults.set(Data("not json".utf8), forKey: "dictationShapingPrompts")

    let settings = AppSettings(defaults: defaults)
    #expect(settings.shapingPrompts == ShapingPrompt.defaults)
  }

  @Test func restoringDefaultsReseedsTheShapingPrompts() {
    let defaults = freshDefaults()
    let settings = AppSettings(defaults: defaults)
    settings.promptShapingPromptID = "mine"
    settings.shapingPrompts = [ShapingPrompt(
      id: "mine",
      name: "Mine",
      preInstruction: "",
      postInstruction: "",
      exampleInput: "",
      exampleOutput: ""
    )]

    settings.restoreDefaultShapingPrompts()

    #expect(settings.shapingPrompts == ShapingPrompt.defaults)
    #expect(AppSettings(defaults: defaults).shapingPrompts == ShapingPrompt.defaults)
    // The selection is left alone: an id the seeds do not carry resolves to
    // nil, which is passthrough.
    #expect(settings.promptShapingPromptID == "mine")
  }

  @Test func promptShapingRoundTripsUnderItsKeys() {
    let defaults = freshDefaults()
    let settings = AppSettings(defaults: defaults)
    settings.promptShapingEnabled = true
    settings.promptShapingPromptID = "bullet-lists"

    #expect(defaults.object(forKey: "dictationPromptShapingEnabled") as? Bool == true)
    #expect(defaults.string(forKey: "dictationPromptShapingPrompt") == "bullet-lists")

    let reloaded = AppSettings(defaults: defaults)
    #expect(reloaded.promptShapingEnabled)
    #expect(reloaded.promptShapingPromptID == "bullet-lists")
  }

  /// The snapshot resolves the pick to a prompt: nil while shaping is off,
  /// and nil again when the stored id names nothing in the user's list.
  @Test func sessionSnapshotResolvesTheShapingPrompt() {
    let settings = AppSettings(defaults: freshDefaults())
    #expect(settings.sessionSettings.shapingPrompt == nil)

    settings.promptShapingEnabled = true
    settings.promptShapingPromptID = "bullet-lists"
    #expect(settings.sessionSettings.shapingPrompt?.id == "bullet-lists")

    settings.promptShapingPromptID = "no-such-prompt"
    #expect(settings.sessionSettings.shapingPrompt == nil)
  }

  /// The session runs the user's edit, not the seed the id started as.
  @Test func sessionSnapshotResolvesTheShapingPromptFromTheEditedList() {
    let settings = AppSettings(defaults: freshDefaults())
    settings.promptShapingEnabled = true
    settings.promptShapingPromptID = "tighten-grammar"
    settings.shapingPrompts[0].preInstruction = "Fix everything."

    #expect(settings.sessionSettings.shapingPrompt?.preInstruction == "Fix everything.")
  }

  /// The snapshot carries the whole library while shaping is on — the
  /// arrows cycle the session's own list — and an empty one while it is
  /// off, so an off session has nothing to cycle.
  @Test func sessionSnapshotCapturesTheShapingLibraryOnlyWhileOn() {
    let settings = AppSettings(defaults: freshDefaults())
    #expect(settings.sessionSettings.shapingLibrary.isEmpty)

    settings.promptShapingEnabled = true
    #expect(settings.sessionSettings.shapingLibrary == settings.shapingPrompts)

    settings.promptShapingEnabled = false
    #expect(settings.sessionSettings.shapingLibrary.isEmpty)
  }

  @Test func deletingTheSelectedPromptFallsBackToPassthrough() {
    let settings = AppSettings(defaults: freshDefaults())
    settings.promptShapingEnabled = true
    settings.promptShapingPromptID = "tighten-grammar"
    settings.shapingPrompts.removeAll { $0.id == "tighten-grammar" }

    #expect(settings.sessionSettings.shapingPrompt == nil)
  }

  @Test func sessionSnapshotCapturesTheInsertionDestination() {
    let settings = AppSettings(defaults: freshDefaults())
    settings.insertionDestination = .clipboardOnly

    let snapshot = settings.sessionSettings
    settings.insertionDestination = .both

    #expect(snapshot.insertionDestination == .clipboardOnly)
  }

  /// The stored value is a plain number rather than a named case, so a
  /// value outside the supported range has to survive the trip.
  @Test func storedHUDSizeOutsideTheRangeComesBackClamped() {
    let defaults = freshDefaults()
    defaults.set(0.05, forKey: "hudScale")

    let settings = AppSettings(defaults: defaults)
    #expect(settings.sessionSettings.hudMetrics.scale == HUDMetrics.minimumScale)
  }

  @Test func storedSoundVolumeOutsideTheRangeComesBackClamped() {
    let defaults = freshDefaults()
    defaults.set(1.4, forKey: "dictationSoundVolume")
    #expect(AppSettings(defaults: defaults).dictationSoundVolume == 1)

    defaults.set(-0.4, forKey: "dictationSoundVolume")
    #expect(AppSettings(defaults: defaults).dictationSoundVolume == 0)
  }

  @Test func assignedSoundVolumeOutsideTheRangeIsClampedBeforePersistence() {
    let defaults = freshDefaults()
    let settings = AppSettings(defaults: defaults)

    settings.dictationSoundVolume = 1.4
    #expect(settings.dictationSoundVolume == 1)
    #expect(defaults.double(forKey: "dictationSoundVolume") == 1)

    settings.dictationSoundVolume = -0.4
    #expect(settings.dictationSoundVolume == 0)
    #expect(defaults.double(forKey: "dictationSoundVolume") == 0)
  }
}
