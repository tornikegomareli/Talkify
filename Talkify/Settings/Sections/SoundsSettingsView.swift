import SwiftUI

/// The Sounds section: the session sound set and its begin/end preview.
/// Preview disables itself while playing, waits out the Begin sound's real
/// duration, and a set change stops playback (CONTEXT.md).
struct SoundsSettings: View {
    @Bindable var settings: AppSettings
    let sounds: DictationHUDSounds

    @State private var isPreviewing = false
    @State private var previewTask: Task<Void, Never>?

    var body: some View {
        SettingsCard(title: "Direct Dictation") {
            SettingsPickerRow(
                title: "Sound set",
                description: "The sounds used when a session begins and ends",
                options: DictationSoundSet.settingsCases,
                optionLabel: { $0.rawValue },
                selection: $settings.soundSet
            )

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
                    isPreviewing || !sounds.hasPreviewSounds(for: settings.soundSet)
                )
            }
        }
        .onChange(of: settings.soundSet) {
            cancelPreview()
        }
        .onDisappear {
            cancelPreview()
        }
    }

    private func playPreview() {
        let set = settings.soundSet
        let delay = max(sounds.beginDuration(for: set), 0) + 0.1
        isPreviewing = true
        sounds.playBegin(using: set)

        previewTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            sounds.playEnd(using: set)
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
