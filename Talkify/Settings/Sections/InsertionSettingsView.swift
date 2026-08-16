import SwiftUI

/// The Insertion section: how finalized dictation text is delivered to the
/// focused app. Paste is the default; Typing posts Unicode keyboard events
/// for editors that refuse synthetic ⌘V (CONTEXT.md).
struct InsertionSettingsView: View {
  @Bindable var settings: AppSettings

  @Environment(\.colorSchemeContrast) private var contrast

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      SettingsCard(title: "Method") {
        SettingsPickerRow(
          title: "Insert text by",
          description: "Paste keeps your clipboard intact and restores it after use",
          options: TextInsertionService.InsertionMethod.allCases,
          optionLabel: { method in
            switch method {
            case .paste: "Paste"
            case .typing: "Typing"
            }
          },
          selection: $settings.insertionMethod,
          controlWidth: 240
        )
      }

      // Informational only: the choice is app-agnostic, so this stays a
      // footnote telling users when the non-default method earns its keep.
      VStack(alignment: .leading, spacing: 2) {
        Text(
          "Paste works in most apps. Switch to Typing when an app ignores "
            + "dictated text or pastes it somewhere unexpected — terminals, "
            + "virtual machines, and some editors refuse pasted events but "
            + "accept typed ones. Typing never touches the clipboard, and "
            + "line breaks arrive as Return presses."
        )
          .font(.caption)
          .foregroundStyle(.white.opacity(contrast == .increased ? 0.7 : 0.45))
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(.horizontal, 6)
    }
  }
}
