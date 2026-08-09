import AppKit
import Testing
@testable import Talkify

@MainActor
struct SettingsWindowTests {
    @Test func controllerBuildsAFixedBorderlessWindow() throws {
        let settings = AppSettings.previewStore()
        let controller = SettingsWindowController(
            settings: settings,
            sounds: DictationHUDSounds(),
            runtimeState: SettingsRuntimeState()
        )
        let window = try #require(controller.window)
        #expect(window.title == "Talkify Settings")
        #expect(window.styleMask.contains(.borderless))
        #expect(!window.styleMask.contains(.resizable))
        #expect(window.level == .normal)
        #expect(!window.isOpaque)
        #expect(!window.isReleasedWhenClosed)
        #expect(window.contentRect(forFrameRect: window.frame).size == NSSize(width: 860, height: 600))
        #expect(window.minSize == window.maxSize)
    }

    @Test func settingsSectionsStayFocusedOnImplementedFeatures() {
        #expect(SettingsSection.allCases == [.appearance, .sounds])
        #expect(SettingsSectionGroup.settings.sections == [.appearance, .sounds])
    }

    @Test func appearanceOptionsFollowTheSelectedVisual() {
        #expect(SettingsView.showsWaveformOptions(for: .waveform))
        #expect(!SettingsView.showsWaveformOptions(for: .glow))
        #expect(!SettingsView.showsWaveformOptions(for: .compact))
        #expect(SettingsView.showsGlowOptions(for: .glow))
        #expect(!SettingsView.showsGlowOptions(for: .waveform))
        #expect(!SettingsView.showsGlowOptions(for: .compact))
    }

    @Test func releaseMetadataExcludesUnlicensedOptions() {
        #expect(DictationSoundSet.synth8.isShippable)
        #expect(!DictationSoundSet.pop.isShippable)
        #expect(HUDGlowCenterStyle.particles.isShippable)
        #expect(!HUDGlowCenterStyle.siriOrb.isShippable)
    }
}
