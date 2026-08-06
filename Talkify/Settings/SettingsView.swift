import SwiftUI

/// The Settings form: sounds, the voice visual, and the waveform style.
/// Bound straight to AppSettings, so every change persists immediately and
/// the next Direct Dictation session uses it.
struct SettingsView: View {
    @Bindable var settings: AppSettings
    let sounds: DictationHUDSounds

    var body: some View {
        Form {
            Section("Sounds") {
                Picker("Session sounds", selection: $settings.soundSet) {
                    ForEach(DictationSoundSet.allCases, id: \.self) { set in
                        Text(set.rawValue).tag(set)
                    }
                }
                Button("Preview") {
                    Task { @MainActor in
                        sounds.playBegin()
                        try? await Task.sleep(for: .milliseconds(600))
                        sounds.playEnd()
                    }
                }
            }

            Section("Voice visual") {
                Picker("While listening", selection: $settings.voiceVisual) {
                    ForEach(HUDVoiceVisualStyle.allCases, id: \.self) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
                .pickerStyle(.segmented)

                if settings.voiceVisual == .waveform {
                    Picker("Waveform style", selection: $settings.waveformStyle) {
                        ForEach(HUDWaveformStyle.allCases, id: \.self) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                }
            }

            // Glow Lab (prototype): feel-test knobs for the Edge Glow;
            // delete this section with the lab once the picks are made (#12).
            if settings.voiceVisual == .glow {
                Section("Glow Lab (prototype)") {
                    Picker("Palette", selection: $settings.glowPalette) {
                        ForEach(HUDGlowPalette.allCases, id: \.self) { palette in
                            Text(palette.rawValue).tag(palette)
                        }
                    }
                    Toggle("Voice → brightness", isOn: $settings.glowVoiceBrightness)
                    Toggle("Voice → beam thickness", isOn: $settings.glowVoiceThickness)
                    Toggle("Voice → reach", isOn: $settings.glowVoiceReach)
                    Toggle("Voice → particle count", isOn: $settings.glowVoiceParticleCount)
                    Toggle("Voice → particle size", isOn: $settings.glowVoiceParticleSize)
                    Toggle("Syllable bursts", isOn: $settings.glowSyllableBursts)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview {
    SettingsView(
        settings: AppSettings.previewStore(),
        sounds: DictationHUDSounds(settings: AppSettings.previewStore())
    )
}
