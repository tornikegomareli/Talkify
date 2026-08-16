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
  /// Which row is armed, and the keys clicked on the keyboard so far. Only one
  /// row can be armed, so the section owns this rather than each recorder.
  @State private var armed: Role?
  @State private var picked: [Int64] = []

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
      keyboardPanel
      keysCard
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

  // Untitled: the drawing says what it is, and the lit keys are the label.
  private var keyboardPanel: some View {
    // Explicitly typed: a ternary yielding an optional closure sends the type
    // checker off a cliff inside a view builder.
    let onPick: ((Int64) -> Void)? = armed == nil ? nil : { keyCode in pick(keyCode) }
    return KeyboardMapView(
      layout: layout,
      highlights: highlights,
      picked: Set(picked),
      onPick: onPick
    )
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
  }

  private var keysCard: some View {
    SettingsCard(title: "Keys") {
      row(
        .dictation,
        title: "Direct Dictation",
        binding: $settings.dictationTriggerBinding,
        allowsBareModifier: true,
        description: "Hold %@ to talk, or tap it to keep listening hands-free."
      )

      if settings.isSecondLanguageEnabled {
        row(
          .secondLanguage,
          title: "Second Language",
          binding: $settings.secondaryTriggerBinding,
          allowsBareModifier: true,
          description: "Hold %@ to dictate in your other language."
        )
      }

      row(
        .readAloud,
        title: "Read Aloud",
        binding: $settings.readAloudBinding,
        allowsBareModifier: false,
        description: "Press %@ to read the selection, again to stop."
      )
    }
  }

  private func row(
    _ role: Role,
    title: String,
    binding: Binding<KeyBinding>,
    allowsBareModifier: Bool,
    /// A sentence with %@ where the bound keys go, so it renames itself with
    /// the binding.
    description: String
  ) -> some View {
    KeyRecorderView(
      keyBinding: binding,
      allowsBareModifier: allowsBareModifier,
      isRecording: Binding(
        get: { armed == role },
        set: { isArmed in
          armed = isArmed ? role : nil
          picked = []
        }
      ),
      onRecordingChanged: { settings.isRecordingKeybind = $0 }
    ) { keyBinding, isRecording in
      let caps = KeyboardMap.caps(for: keyBinding, layout: layout)
      ShortcutRow(
        caps: caps,
        title: title,
        description: String(format: description, caps.joined(separator: " ")),
        isRecording: isRecording,
        accent: role.color,
        pickedCaps: isRecording ? pickedCaps : [],
        onConfirm: isRecording && !picked.isEmpty ? { commit(picked) } : nil
      )
    }
    .onHover { hovered = $0 ? role : nil }
  }

  /// A modifier waits for the rest of the combination; anything else finishes
  /// it. That is what makes ⌥ then fn reachable by clicking.
  private func pick(_ keyCode: Int64) {
    if KeyboardMap.combiningModifiers.contains(keyCode) {
      if let index = picked.firstIndex(of: keyCode) {
        picked.remove(at: index)
      } else {
        picked.append(keyCode)
      }
      return
    }
    commit(picked + [keyCode])
  }

  private func commit(_ clicked: [Int64]) {
    guard let role = armed,
       let binding = KeyboardMap.binding(forClicked: clicked, layout: layout)
    else { return }
    self.binding(for: role).wrappedValue = binding
    armed = nil
    picked = []
  }

  private func binding(for role: Role) -> Binding<KeyBinding> {
    switch role {
    case .dictation: $settings.dictationTriggerBinding
    case .secondLanguage: $settings.secondaryTriggerBinding
    case .readAloud: $settings.readAloudBinding
    }
  }

  private var pickedCaps: [String] {
    guard let binding = KeyboardMap.binding(forClicked: picked, layout: layout) else { return [] }
    return KeyboardMap.caps(for: binding, layout: layout)
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
  /// What has been clicked on the keyboard so far, shown in place of the
  /// binding while the row is armed.
  var pickedCaps: [String] = []
  /// Present once something is picked; a bare modifier has no following key to
  /// finish it, so it needs somewhere to say "that one".
  var onConfirm: (() -> Void)?

  @Environment(\.colorSchemeContrast) private var contrast

  var body: some View {
    HStack(spacing: 15) {
      HStack(spacing: 6) {
        if isRecording, !pickedCaps.isEmpty {
          ForEach(Array(pickedCaps.enumerated()), id: \.offset) { _, symbol in
            cap(symbol, isArmed: true)
          }
        } else if isRecording {
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
        Text(isRecording ? armedPrompt : description)
          .font(.system(size: 11.5))
          .foregroundStyle(.white.opacity(contrast == .increased ? 0.72 : 0.48))
          .fixedSize(horizontal: false, vertical: true)
          .multilineTextAlignment(.leading)
      }

      Spacer(minLength: 0)

      if let onConfirm {
        Button("Use these", action: onConfirm)
          .buttonStyle(SettingsButtonStyle())
      }
    }
    .padding(.vertical, 11)
    .contentShape(Rectangle())
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(.white.opacity(contrast == .increased ? 0.16 : 0.07))
        .frame(height: 1)
    }
  }

  private var armedPrompt: String {
    pickedCaps.isEmpty
      ? "Press the keys you want, or click them on the keyboard above."
      : "Click one more key to finish, or use what you picked."
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
