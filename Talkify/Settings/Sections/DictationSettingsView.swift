import SwiftUI

/// The Dictation section: where a finished Direct Dictation session's text
/// goes. The choice is captured into the session settings snapshot at
/// session start (CONTEXT.md).
struct DictationSettingsView: View {
  @Bindable var settings: AppSettings

  var body: some View {
    SettingsCard(title: "Insertion") {
      SettingsPickerRow(
        title: "Deliver text by",
        description: "Insert into the app pastes into the control you were "
          + "typing in and restores your clipboard, as Direct Dictation has "
          + "always worked. Copy to the clipboard never pastes. Insert and "
          + "copy pastes and leaves the text on the clipboard.",
        options: InsertionDestination.allCases,
        optionLabel: { $0.title },
        selection: $settings.insertionDestination
      )
    }
  }
}
