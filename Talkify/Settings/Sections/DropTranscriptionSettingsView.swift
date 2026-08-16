import AppKit
import SwiftUI

/// The Drop Transcription section: where a transcript nobody caught is written,
/// and a reminder of the gesture that produces one.
struct DropTranscriptionSettingsView: View {
  @Bindable var settings: AppSettings

  var body: some View {
    VStack(spacing: 16) {
      DropPreviewCard(settings: settings)

      SettingsCard(title: "Transcripts") {
        SettingsPickerRow(
          title: "Save to",
          description: "Where a transcript goes when you don't drag it out of the HUD",
          options: TranscriptDestination.Preference.allCases,
          optionLabel: { $0.rawValue },
          selection: $settings.transcriptDestination
        )

        if settings.transcriptDestination == .chosenFolder {
          SettingsRow(
            title: "Folder",
            description: folderDescription
          ) {
            Button("Choose…") { chooseFolder() }
              .buttonStyle(SettingsButtonStyle())
          }
        }
      }

      SettingsCard(title: "How it works") {
        SettingsRow(
          title: "Drag to the notch",
          description: "Drag an audio or video file to the top of the screen "
            + "and the HUD opens to take it. When it finishes, drag the "
            + "transcript out of the HUD to wherever you want it, or click it "
            + "to copy the text. Leave it and it saves itself."
        ) {
          EmptyView()
        }
      }
    }
  }

  /// Says where the transcript actually lands, rather than only naming the
  /// pick: an unset folder silently falls back, and that should not surprise.
  private var folderDescription: String {
    guard let folder = settings.transcriptFolder else {
      return "No folder chosen yet, so transcripts go to the Desktop"
    }
    return folder.path(percentEncoded: false)
  }

  private func chooseFolder() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.prompt = "Choose"
    panel.message = "Choose where transcripts are saved."
    NSApp.activate()
    guard panel.runModal() == .OK, let url = panel.url else { return }
    settings.transcriptFolder = url
  }
}
