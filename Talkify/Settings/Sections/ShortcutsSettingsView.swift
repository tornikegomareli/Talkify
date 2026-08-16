import SwiftUI

/// The Shortcuts section: the user's own keyboard with the bound keys lit,
/// above System Settings-style recorders for each binding. Arming a recorder
/// flags `isRecordingKeybind` so the event tap pauses.
struct ShortcutsSettingsView: View {
  @Bindable var settings: AppSettings

  /// Read once and refreshed when the input source changes, rather than on
  /// every redraw: translating the whole board is cheap but not free, and the
  /// answer only moves when the user switches language or swaps keyboards.
  @State private var layout = KeyboardLayout.ansiFallback
  @State private var hovered: Binding?

  /// Which binding a row belongs to. The colors are the lit keys' colors.
  private enum Binding: Hashable {
    case dictation
    case secondLanguage
    case readAloud

    var color: Color {
      switch self {
      case .dictation: SettingsTheme.accent
      case .secondLanguage: Color(red: 0.45, green: 0.82, blue: 0.6)
      case .readAloud: Color(red: 0.95, green: 0.7, blue: 0.35)
      }
    }
  }

  var body: some View {
    VStack(spacing: 16) {
      // Untitled: the drawing says what it is, and the lit keys are the label.
      KeyboardMapView(layout: layout, highlights: highlights)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 18)
        .padding(.horizontal, 16)
        .background(
          SettingsTheme.card,
          in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(.white.opacity(0.09), lineWidth: 1)
        }

      SettingsCard(title: "Keys") {
        recorderRow(
          .dictation,
          title: "Dictation Trigger",
          description: "Hold to dictate, tap to keep it listening",
          binding: $settings.dictationTriggerBinding,
          allowsBareModifier: true
        )

        if settings.isSecondLanguageEnabled {
          recorderRow(
            .secondLanguage,
            title: "Second Language",
            description: "The same gesture, in your other dictation language",
            binding: $settings.secondaryTriggerBinding,
            allowsBareModifier: true
          )
        }

        recorderRow(
          .readAloud,
          title: "Read Aloud",
          description: "Speaks the selected text out loud",
          binding: $settings.readAloudBinding,
          allowsBareModifier: false
        )
      }
    }
    .task {
      layout = KeyboardLayout.current()
    }
    .onReceive(
      DistributedNotificationCenter.default().publisher(
        for: KeyboardLayout.inputSourceChanged
      )
    ) { _ in
      layout = KeyboardLayout.current()
    }
  }

  private func recorderRow(
    _ role: Binding,
    title: String,
    description: String,
    binding: SwiftUI.Binding<KeyBinding>,
    allowsBareModifier: Bool
  ) -> some View {
    SettingsRow(title: title, description: description) {
      KeyRecorderView(
        keyBinding: binding,
        allowsBareModifier: allowsBareModifier,
        onRecordingChanged: { settings.isRecordingKeybind = $0 }
      )
    }
    .onHover { hovered = $0 ? role : nil }
  }

  private var highlights: [KeyboardMapView.Highlight] {
    var result: [KeyboardMapView.Highlight] = [
      highlight(.dictation, settings.dictationTriggerBinding),
      highlight(.readAloud, settings.readAloudBinding),
    ]
    if settings.isSecondLanguageEnabled {
      result.append(highlight(.secondLanguage, settings.secondaryTriggerBinding))
    }
    return result
  }

  private func highlight(_ role: Binding, _ keyBinding: KeyBinding) -> KeyboardMapView.Highlight {
    KeyboardMapView.Highlight(
      keyCodes: KeyboardMap.highlighted(for: keyBinding),
      color: role.color,
      isEmphasized: hovered == role || hovered == nil
    )
  }
}
