import SwiftUI

/// The Sounds section: session playback controls and the begin/end preview.
/// Preview disables itself while playing, waits out the Begin sound's real
/// duration, and a preference change stops playback (CONTEXT.md).
struct SoundsSettingsView: View {
  @Bindable var settings: AppSettings
  let sounds: HUDSounds

  @State private var isPreviewing = false
  @State private var previewTask: Task<Void, Never>?

  var body: some View {
    SettingsCard(title: "While dictating") {
      SettingsRow(
        title: "Lower other audio",
        description: "Turn the volume down while a session listens, and put it "
          + "back afterwards. Moves the system output, so it quiets everything"
      ) {
        Toggle("Lower other audio", isOn: $settings.duckOtherAudioWhileDictating)
          .labelsHidden()
          .toggleStyle(.switch)
      }
    }

    SettingsCard(title: "Sounds") {
      SettingsRow(
        title: "Play sounds",
        description: "Play cues when dictation and file transcription begin, "
          + "end, and deliver their text"
      ) {
        Toggle("Play sounds", isOn: $settings.dictationSoundsEnabled)
          .labelsHidden()
          .toggleStyle(.switch)
      }

      SettingsPickerRow(
        title: "Sound set",
        description: "The sounds used when a session begins and ends",
        options: DictationSoundSet.settingsCases,
        optionLabel: { $0.rawValue },
        selection: $settings.soundSet
      )
      .disabled(!settings.dictationSoundsEnabled)

      SettingsSliderRow(
        title: "Volume",
        description: "The volume of every sound Talkify plays",
        value: $settings.dictationSoundVolume,
        range: DictationSoundSettings.volumeRange,
        valueLabel: { "\(Int(($0 * 100).rounded()))%" }
      )
      .disabled(!settings.dictationSoundsEnabled)

      SettingsRow(
        title: "Preview",
        description: "Play the selected begin and end sounds"
      ) {
        Button {
          playPreview()
        } label: {
          Text(isPreviewing ? "Playing…" : "Play preview")
        }
        .buttonStyle(SettingsButtonStyle())
        .disabled(
          isPreviewing
            || !settings.dictationSoundsEnabled
            || !sounds.hasPreviewSounds(for: settings.soundSet)
        )
      }
    }
    .onChange(of: settings.soundSet) {
      cancelPreview()
    }
    .onChange(of: settings.dictationSoundsEnabled) {
      cancelPreview()
    }
    .onChange(of: settings.dictationSoundVolume) {
      cancelPreview()
    }
    .onDisappear {
      cancelPreview()
    }
  }

  private func playPreview() {
    let soundSettings = settings.sessionSettings.sounds
    let delay = max(sounds.beginDuration(for: soundSettings.set), 0) + 0.1
    isPreviewing = true
    sounds.playBegin(using: soundSettings)

    previewTask = Task { @MainActor in
      try? await Task.sleep(for: .seconds(delay))
      guard !Task.isCancelled else { return }
      sounds.playEnd(using: soundSettings)
      isPreviewing = false
      previewTask = nil
    }
  }

  private func cancelPreview() {
    previewTask?.cancel()
    previewTask = nil
    sounds.stopAll()
    isPreviewing = false
  }
}
