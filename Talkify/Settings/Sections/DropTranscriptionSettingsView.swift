import AppKit
import SwiftUI

/// The Drop Transcription section: where a finished transcript is written, and
/// a reminder of the gesture that produces one.
struct DropTranscriptionSettingsView: View {
  @Bindable var settings: AppSettings

  var body: some View {
    VStack(spacing: 16) {
      SettingsCard(title: "Transcripts") {
        SettingsPickerRow(
          title: "Save to",
          description: "Where a finished transcript is written",
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
            + "transcript straight out of the HUD."
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
