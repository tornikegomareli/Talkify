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

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// Built once: a publisher constructed inside `body` is a new subscription
  /// on every update.
  private static let inputSourceChanges = DistributedNotificationCenter.default()
    .publisher(for: KeyboardLayout.inputSourceChanged)

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
    .onReceive(Self.inputSourceChanges) { _ in
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
      // Armed, the border lights: nothing else on screen says the drawing
      // just became something you can click.
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(
          isArmed ? SettingsTheme.accent.opacity(0.85) : .white.opacity(0.09),
          lineWidth: isArmed ? 1.5 : 1
        )
    }
    .shadow(
      color: isArmed ? SettingsTheme.accent.opacity(0.28) : .clear,
      radius: isArmed ? 12 : 0
    )
    .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isArmed)
  }

  private var isArmed: Bool { armed != nil }

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

  private func pick(_ keyCode: Int64) {
    switch ShortcutAssignment.click(keyCode, picked: picked) {
    case let .picking(selection): picked = selection
    case let .complete(selection): commit(selection)
    }
  }

  private func commit(_ clicked: [Int64]) {
    guard let role = armed,
       let binding = ShortcutAssignment.binding(forClicked: clicked, layout: layout)
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
    guard let binding = ShortcutAssignment.binding(forClicked: picked, layout: layout)
    else { return [] }
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
