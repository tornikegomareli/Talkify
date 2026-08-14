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
      runtimeState: SettingsRuntimeState(),
      usageTracker: UsageTracker(store: UsageStore(
        fileURL: FileManager.default.temporaryDirectory
          .appending(path: "TalkifySettingsWindowTests-" + UUID().uuidString + ".json")
      )),
      updater: SparkleUpdaterService()
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
    let expected: [SettingsSection] = [
      .appearance, .sounds, .readAloud, .language, .shortcuts, .updates, .insights,
    ]
    #expect(SettingsSection.allCases == expected)
    #expect(SettingsSectionGroup.settings.sections == expected)
  }

  @Test func appearanceOptionsFollowTheSelectedVisual() {
    #expect(AppearanceSettingsView.showsWaveformOptions(for: .waveform))
    #expect(!AppearanceSettingsView.showsWaveformOptions(for: .glow))
    #expect(!AppearanceSettingsView.showsWaveformOptions(for: .compact))
    #expect(AppearanceSettingsView.showsGlowOptions(for: .glow))
    #expect(!AppearanceSettingsView.showsGlowOptions(for: .waveform))
    #expect(!AppearanceSettingsView.showsGlowOptions(for: .compact))
  }

  @Test func releaseMetadataExcludesUnlicensedOptions() {
    #expect(DictationSoundSet.synth8.isShippable)
    #expect(!DictationSoundSet.pop.isShippable)
    #expect(HUDGlowCenterStyle.particles.isShippable)
    #expect(!HUDGlowCenterStyle.siriOrb.isShippable)
  }
}
