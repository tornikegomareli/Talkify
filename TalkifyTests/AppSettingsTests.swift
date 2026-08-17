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
    first.recognitionLocaleIdentifier = "fr_FR"
    first.secondaryRecognitionLocaleIdentifier = "it_IT"
    first.secondaryTriggerBinding = .fnTrigger

    let second = AppSettings(defaults: defaults)
    #expect(second.recognitionLocaleIdentifier == "fr_FR")
    #expect(second.secondaryRecognitionLocaleIdentifier == "it_IT")
    #expect(second.secondaryTriggerBinding == .fnTrigger)
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

  @Test func languageTagsAreTwoLetterUppercase() {
    #expect(SpeechLanguageCatalog.tag(for: Locale(identifier: "de_DE")) == "DE")
    #expect(SpeechLanguageCatalog.tag(for: Locale(identifier: "en_US")) == "EN")
    #expect(SpeechLanguageCatalog.tag(for: Locale(identifier: "yue_CN")) == "YU")
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
