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
        #expect(settings.voiceVisual == .waveform)
        #expect(settings.waveformStyle == .chartLine)
        #expect(settings.revealStyle == .slide)
        #expect(settings.longDraftStyle == .growDown)
        #expect(settings.readAloudVoiceID.isEmpty)
        #expect(settings.dictationTriggerBinding == .fnTrigger)
        #expect(settings.readAloudBinding == .optionEscape)
    }

    @Test func everyPreferenceRoundTrips() {
        let defaults = freshDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.soundSet = .chime
        settings.voiceVisual = .glow
        settings.waveformStyle = .dots
        settings.revealStyle = .bloom
        settings.longDraftStyle = .shrinkToFit
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
        #expect(reloaded.voiceVisual == .glow)
        #expect(reloaded.waveformStyle == .dots)
        #expect(reloaded.revealStyle == .bloom)
        #expect(reloaded.longDraftStyle == .shrinkToFit)
        #expect(reloaded.readAloudVoiceID == "com.apple.voice.premium.en-US.Zoe")
        #expect(reloaded.dictationTriggerBinding == rightCommandTrigger)
        #expect(reloaded.readAloudBinding == f5Binding)
    }

    @Test func storedKeysMatchTheHistoricalNames() {
        let defaults = freshDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.soundSet = .click
        settings.voiceVisual = .glow
        settings.waveformStyle = .silver
        settings.revealStyle = .drift
        settings.longDraftStyle = .tailOnly
        settings.readAloudVoiceID = "com.apple.voice.enhanced.en-GB.Jamie"

        #expect(defaults.string(forKey: "dictationSoundSet") == "Click")
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

        #expect(snapshot.soundSet == .synth8)
        #expect(snapshot.voiceVisual == .waveform)
        #expect(snapshot.waveformStyle == .chartLine)
        #expect(snapshot.revealStyle == .slide)
        #expect(snapshot.longDraftStyle == .growDown)
        #expect(snapshot.glowPalette == .spectrum)
        #expect(snapshot.glowCenter == .particles)
    }
}
