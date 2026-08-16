import SwiftUI

/// The Shortcuts section: the user's own keyboard with the bound keys lit,
/// above one row per binding. The whole row is the recorder — clicking it arms,
/// and the next keystroke becomes the binding — so the keycaps on the leading
/// edge are the binding rather than a control sitting beside it.
struct ShortcutsSettingsView: View {
  @Bindable var settings: AppSettings

  /// Read once and refreshed when the input source changes, rather than on
  /// every redraw: translating the whole board is cheap but not free, and the
  /// answer only moves when the user switches language or swaps keyboards.
  @State private var layout = KeyboardLayout.ansiFallback
  @State private var hovered: Role?

  /// Which binding a row belongs to. The colors are the lit keys' colors.
  private enum Role: Hashable {
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
        row(
          .dictation,
          title: "Direct Dictation",
          binding: $settings.dictationTriggerBinding,
          allowsBareModifier: true
        ) { keys in
          "Hold \(keys) to talk, or tap it to keep listening hands-free."
        }

        if settings.isSecondLanguageEnabled {
          row(
            .secondLanguage,
            title: "Second Language",
            binding: $settings.secondaryTriggerBinding,
            allowsBareModifier: true
          ) { keys in
            "Hold \(keys) to dictate in your other language."
          }
        }

        row(
          .readAloud,
          title: "Read Aloud",
          binding: $settings.readAloudBinding,
          allowsBareModifier: false
        ) { keys in
          "Press \(keys) to read the selection, again to stop."
        }
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

  private func row(
    _ role: Role,
    title: String,
    binding: Binding<KeyBinding>,
    allowsBareModifier: Bool,
    description: @escaping (String) -> String
  ) -> some View {
    KeyRecorderView(
      keyBinding: binding,
      allowsBareModifier: allowsBareModifier,
      onRecordingChanged: { settings.isRecordingKeybind = $0 }
    ) { keyBinding, isRecording in
      let caps = KeyboardMap.caps(for: keyBinding, layout: layout)
      ShortcutRow(
        caps: caps,
        title: title,
        description: description(caps.joined(separator: " ")),
        isRecording: isRecording,
        accent: role.color
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

  private func highlight(_ role: Role, _ keyBinding: KeyBinding) -> KeyboardMapView.Highlight {
    KeyboardMapView.Highlight(
      keyCodes: KeyboardMap.highlighted(for: keyBinding),
      color: role.color,
      isEmphasized: hovered == role || hovered == nil
    )
  }
}

/// One binding: its keys as separate caps on the leading edge, then what it
/// does. Each cap is one physical key, rather than a single label with the
/// whole combination crammed into it.
private struct ShortcutRow: View {
  let caps: [String]
  let title: String
  let description: String
  let isRecording: Bool
  let accent: Color

  @Environment(\.colorSchemeContrast) private var contrast

  var body: some View {
    HStack(spacing: 15) {
      HStack(spacing: 6) {
        if isRecording {
          cap("…", isArmed: true)
        } else {
          ForEach(Array(caps.enumerated()), id: \.offset) { _, symbol in
            cap(symbol, isArmed: false)
          }
        }
      }

      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(.white)
        Text(isRecording ? "Press the keys you want to use." : description)
          .font(.system(size: 11.5))
          .foregroundStyle(.white.opacity(contrast == .increased ? 0.72 : 0.48))
          .fixedSize(horizontal: false, vertical: true)
          .multilineTextAlignment(.leading)
      }

      Spacer(minLength: 0)
    }
    .padding(.vertical, 11)
    .contentShape(Rectangle())
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(.white.opacity(contrast == .increased ? 0.16 : 0.07))
        .frame(height: 1)
    }
  }

  private func cap(_ symbol: String, isArmed: Bool) -> some View {
    let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
    return Text(symbol)
      .font(.system(size: symbol.count > 2 ? 10 : 13, weight: .medium))
      .foregroundStyle(isArmed ? accent : .white.opacity(0.9))
      .lineLimit(1)
      .minimumScaleFactor(0.6)
      .padding(.horizontal, 4)
      .frame(width: 34, height: 32)
      .background(
        shape.fill(
          LinearGradient(
            colors: [Color(white: 0.16), Color(white: 0.11)],
            startPoint: .top,
            endPoint: .bottom
          )
        )
      )
      .overlay {
        shape.strokeBorder(
          isArmed ? accent.opacity(0.8) : .white.opacity(0.1),
          lineWidth: 1
        )
      }
  }
}
