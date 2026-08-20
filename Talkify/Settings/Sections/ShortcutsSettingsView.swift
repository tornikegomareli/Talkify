import SwiftUI

/// The Shortcuts section: the user's own keyboard with the bound keys lit,
/// above one row per binding. The whole row is the recorder — clicking it arms,
/// and the next keystroke or supported mouse-button press becomes the binding —
/// so the caps on the leading edge are the binding rather than a control
/// sitting beside it.
struct ShortcutsSettingsView: View {
  @Bindable var settings: AppSettings

  /// Read once and refreshed when the input source changes, rather than on
  /// every redraw: translating the whole board is cheap but not free, and the
  /// answer only moves when the user switches language or swaps keyboards.
  @State private var layout = KeyboardLayout.ansiFallback
  @State private var hovered: BindingRole?
  /// Which row is armed, and the keys clicked on the keyboard so far. Only one
  /// row can be armed, so the section owns this rather than each recorder.
  @State private var armed: BindingRole?
  @State private var picked: [Int64] = []

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// Built once: a publisher constructed inside `body` is a new subscription
  /// on every update.
  private static let inputSourceChanges = DistributedNotificationCenter.default()
    .publisher(for: KeyboardLayout.inputSourceChanged)

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
    SettingsCard(title: "Bindings") {
      row(
        .dictation,
        allowsBareModifier: true,
        allowsMouseButton: true,
        sentence: "Hold %@ to talk, or tap it to start and tap again to finish."
      )

      if settings.isSecondLanguageEnabled {
        row(
          .secondLanguage,
          allowsBareModifier: true,
          allowsMouseButton: true,
          sentence: "Hold %@ to dictate in your other language, or tap it the same way."
        )
      }

      row(
        .readAloud,
        allowsBareModifier: false,
        allowsMouseButton: false,
        sentence: "Press %@ to read the selection, again to stop."
      )
    }
  }

  private func row(
    _ role: BindingRole,
    allowsBareModifier: Bool,
    allowsMouseButton: Bool,
    /// A sentence with %@ where the bound keys go, so it renames itself with
    /// the binding.
    sentence: String
  ) -> some View {
    KeyRecorderView(
      keyBinding: binding(for: role),
      allowsBareModifier: allowsBareModifier,
      allowsMouseButton: allowsMouseButton,
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
        title: role.title,
        description: description(sentence, for: keyBinding, in: role, caps: caps),
        isRecording: isRecording,
        accent: role.color,
        acceptsMouseButton: allowsMouseButton,
        isMouseBinding: keyBinding.isMouseButton,
        pickedCaps: isRecording ? pickedCaps : [],
        onConfirm: isRecording && !picked.isEmpty ? { commit(picked) } : nil
      )
    }
    .onHover { hovered = $0 ? role : nil }
  }

  /// What the row says under its title: what the binding does, what it costs
  /// when it is a mouse button, and whether another row already has it.
  private func description(
    _ sentence: String,
    for binding: KeyBinding,
    in role: BindingRole,
    caps: [String]
  ) -> String {
    let named = binding.isMouseButton ? binding.label : caps.joined(separator: " ")
    var description = String(format: sentence, named)
    if binding.isMouseButton {
      description += " This button keeps its usual action unless that exact combination is pressed."
    }
    if let other = settings.roleUsing(binding, excluding: role) {
      description += " Also used by \(other.title)."
    }
    return description
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

  private func binding(for role: BindingRole) -> Binding<KeyBinding> {
    Binding(
      get: { settings.binding(for: role) },
      set: { settings.setBinding($0, for: role) }
    )
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

  private func highlight(
    _ role: BindingRole,
    _ keyBinding: KeyBinding
  ) -> KeyboardMapView.Highlight {
    KeyboardMapView.Highlight(
      keyCodes: KeyboardMap.highlighted(for: keyBinding),
      color: role.color,
      isEmphasized: hovered == role || hovered == nil
    )
  }
}

/// The color that identifies a binding, both where its keys light on the drawn
/// keyboard and on its own row.
private extension BindingRole {
  var color: Color {
    switch self {
    case .dictation: SettingsTheme.accent
    case .secondLanguage: Color(red: 0.45, green: 0.82, blue: 0.6)
    case .readAloud: Color(red: 0.95, green: 0.7, blue: 0.35)
    }
  }
}
