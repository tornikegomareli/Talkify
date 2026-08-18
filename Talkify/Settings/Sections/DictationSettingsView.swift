import SwiftUI

/// The Dictation section: what happens to the words once a session ends.
///
/// Pasting and restoring the clipboard is right for most people and stays the
/// default. The other two picks exist for people it fights: someone who wants
/// to place the text themselves, and anyone whose clipboard-history manager
/// never keeps a dictation because the restore puts the old clipboard back
/// over it (CONTEXT.md).
struct DictationSettingsView: View {
  @Bindable var settings: AppSettings

  var body: some View {
    SettingsCard(title: "Finished text") {
      SettingsPickerRow(
        title: "Send it to",
        description: settings.insertionDestination.detail,
        options: InsertionDestination.allCases,
        optionLabel: \.title,
        selection: $settings.insertionDestination,
        controlWidth: 260
      )
    }
  }
}
