import SwiftUI

/// The Shortcuts section: System Settings-style recorders for the Dictation
/// Trigger (single key, bare modifiers allowed) and the Read Aloud combo.
/// Arming a recorder flags `isRecordingKeybind` so the event tap pauses.
struct ShortcutsSettingsView: View {
  @Bindable var settings: AppSettings

  var body: some View {
    SettingsCard(title: "Keys") {
      SettingsRow(title: "Dictation Trigger") {
        KeyRecorderView(
          keyBinding: $settings.dictationTriggerBinding,
          capturesSingleKey: true,
          onRecordingChanged: { settings.isRecordingKeybind = $0 }
        )
      }

      SettingsRow(title: "Read Aloud") {
        KeyRecorderView(
          keyBinding: $settings.readAloudBinding,
          capturesSingleKey: false,
          onRecordingChanged: { settings.isRecordingKeybind = $0 }
        )
      }
    }
  }
}
