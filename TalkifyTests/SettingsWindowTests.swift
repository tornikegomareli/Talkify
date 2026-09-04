import AppKit
import Testing
@testable import Talkify

@MainActor
struct SettingsWindowTests {
  @Test func controllerBuildsAFixedBorderlessWindow() throws {
    let settings = AppSettings.previewStore()
    let controller = SettingsWindowController(
      settings: settings,
      sounds: HUDSounds(),
      runtimeState: SettingsRuntimeState(),
      usageTracker: UsageTracker(store: UsageStore(
        fileURL: FileManager.default.temporaryDirectory
          .appending(path: "TalkifySettingsWindowTests-" + UUID().uuidString + ".json")
      )),
      updater: SparkleUpdaterService(),
      launchAtLogin: LaunchAtLoginService()
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
      .general, .appearance, .sounds, .dictation, .promptShaping,
      .dropTranscription, .readAloud, .language, .shortcuts, .updates, .insights,
    ]
    #expect(SettingsSection.allCases == expected)
    #expect(SettingsSectionGroup.settings.sections == expected)
  }

  @Test func deletingThePickedShapingPromptFallsBackToTheFirst() {
    let prompts = ShapingPrompt.defaults
    let picked = prompts[1].id
    #expect(
      PromptShapingSettingsView.resolvedSelection(picked: picked, in: prompts) == picked
    )
    let remaining = prompts.filter { $0.id != picked }
    #expect(
      PromptShapingSettingsView.resolvedSelection(picked: picked, in: remaining)
        == remaining[0].id
    )
    #expect(PromptShapingSettingsView.resolvedSelection(picked: picked, in: []) == "")
  }

  @Test func appearanceOptionsFollowTheSelectedVisual() {
    #expect(AppearanceSettingsView.showsWaveformOptions(for: .waveform))
    #expect(!AppearanceSettingsView.showsWaveformOptions(for: .glow))
    #expect(!AppearanceSettingsView.showsWaveformOptions(for: .compact))
    #expect(!AppearanceSettingsView.showsWaveformOptions(for: .waveDraft))
    #expect(AppearanceSettingsView.showsGlowPalette(for: .glow))
    #expect(AppearanceSettingsView.showsGlowPalette(for: .waveDraft))
    #expect(!AppearanceSettingsView.showsGlowPalette(for: .waveform))
    #expect(!AppearanceSettingsView.showsGlowPalette(for: .compact))
    #expect(AppearanceSettingsView.showsGlowCenter(for: .glow))
    #expect(!AppearanceSettingsView.showsGlowCenter(for: .waveDraft))
    #expect(!AppearanceSettingsView.showsGlowCenter(for: .waveform))
    #expect(!AppearanceSettingsView.showsLongDraftBehavior(
      for: .waveDraft, reduceMotion: false))
    #expect(AppearanceSettingsView.showsLongDraftBehavior(
      for: .waveDraft, reduceMotion: true))
    #expect(AppearanceSettingsView.showsLongDraftBehavior(
      for: .compact, reduceMotion: false))
    #expect(AppearanceSettingsView.showsWaveDraftRibbon(for: .waveDraft))
    #expect(!AppearanceSettingsView.showsWaveDraftRibbon(for: .waveform))
    #expect(!AppearanceSettingsView.showsWaveDraftRibbon(for: .glow))
  }

  @Test func releaseMetadataExcludesUnlicensedOptions() {
    #expect(DictationSoundSet.synth8.isShippable)
    #expect(!DictationSoundSet.pop.isShippable)
    #expect(HUDGlowCenterStyle.particles.isShippable)
    #expect(!HUDGlowCenterStyle.siriOrb.isShippable)
  }
}
