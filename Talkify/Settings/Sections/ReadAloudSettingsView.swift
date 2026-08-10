import AVFAudio
import SwiftUI

/// The Read Aloud section: the voice pick (enhanced/premium/Personal only),
/// a spoken preview, and the System Settings handoffs for voice downloads
/// and Personal Voice — Talkify cannot download synthesis voices itself
/// (CONTEXT.md).
struct ReadAloudSettings: View {
  @Bindable var settings: AppSettings

  @Environment(\.colorSchemeContrast) private var contrast
  @State private var catalog = VoiceCatalog()
  @State private var previewSynthesizer = AVSpeechSynthesizer()
  @State private var personalVoiceStatus = AVSpeechSynthesizer.personalVoiceAuthorizationStatus

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      SettingsCard(title: "Voice") {
        SettingsPickerRow(
          title: "Read Aloud voice",
          description: catalog.voices.isEmpty
            ? "Only default-quality voices are installed on this Mac"
            : "High-quality voices installed on this Mac",
          options: [""] + catalog.voices.map(\.identifier),
          optionLabel: { identifier in
            guard !identifier.isEmpty else { return "System Default" }
            return catalog.voices
              .first { $0.identifier == identifier }
              .map(VoiceCatalog.label(for:)) ?? identifier
          },
          selection: $settings.readAloudVoiceID,
          controlWidth: 240
        )

        SettingsRow(
          title: "Preview",
          description: "Hear a sample with the selected voice"
        ) {
          Button("Play sample") {
            playPreview()
          }
          .buttonStyle(SettingsButtonStyle())
        }
      }

      SettingsCard(title: "More voices") {
        SettingsRow(
          title: "Download premium voices",
          description: "In System Settings, open Spoken Content → "
            + "System Voice → Manage Voices and download a Premium "
            + "voice (the files are large and download quietly; a "
            + "stuck download usually clears after a restart). New "
            + "voices appear here automatically."
        ) {
          Button("Open System Settings") {
            VoiceCatalog.openVoiceDownloadSettings()
          }
          .buttonStyle(SettingsButtonStyle())
        }

        if personalVoiceStatus == .notDetermined {
          SettingsRow(
            title: "Personal Voice",
            description: "Let Talkify read text in your own trained voice"
          ) {
            Button("Allow Personal Voice") {
              Task {
                personalVoiceStatus = await VoiceCatalog.requestPersonalVoiceAccess()
                catalog.refresh()
              }
            }
            .buttonStyle(SettingsButtonStyle())
          }
        }
      }

      // Informational only: Personal Voice creation is Apple's UI and
      // has no API, so this stays a footnote rather than a feature row.
      VStack(alignment: .leading, spacing: 2) {
        Text(
          "Talkify can also speak in a voice trained on your own "
            + "speech: create a Personal Voice in System Settings → "
            + "Accessibility, then allow Talkify to use it."
        )
        .font(.caption)
        .foregroundStyle(.white.opacity(contrast == .increased ? 0.7 : 0.45))
        .fixedSize(horizontal: false, vertical: true)

        Button("Open Personal Voice settings…") {
          VoiceCatalog.openPersonalVoiceSettings()
        }
        .buttonStyle(.link)
        .font(.caption)
        .tint(SettingsTheme.accent)
      }
      .padding(.horizontal, 6)
    }
  }

  private func playPreview() {
    previewSynthesizer.stopSpeaking(at: .immediate)
    let utterance = AVSpeechUtterance(
      string: "Hi! This is how Talkify will read your text out loud."
    )
    if !settings.readAloudVoiceID.isEmpty,
     let voice = AVSpeechSynthesisVoice(identifier: settings.readAloudVoiceID) {
      utterance.voice = voice
    }
    previewSynthesizer.speak(utterance)
  }
}
