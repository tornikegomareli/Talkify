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
  @State private var hovered: Role?
  /// Which row is armed, and the keys clicked on the keyboard so far. Only one
  /// row can be armed, so the section owns this rather than each recorder.
  @State private var armed: Role?
  @State private var picked: [Int64] = []
  @State private var conflictMessage: String?

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// Built once: a publisher constructed inside `body` is a new subscription
  /// on every update.
  private static let inputSourceChanges = DistributedNotificationCenter.default()
    .publisher(for: KeyboardLayout.inputSourceChanged)

  /// Which binding a row belongs to. The colors identify each binding in the
  /// keyboard highlights and its row.
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

    var title: String {
      switch self {
      case .dictation: "Direct Dictation"
      case .secondLanguage: "Second Language"
      case .readAloud: "Read Aloud"
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
    .onChange(of: armed) { _, role in
      if role != nil { conflictMessage = nil }
    }
    .onChange(of: settings.dictationTriggerBinding) { conflictMessage = nil }
    .onChange(of: settings.secondaryTriggerBinding) { conflictMessage = nil }
    .onChange(of: settings.readAloudBinding) { conflictMessage = nil }
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
        title: "Direct Dictation",
        binding: binding(for: .dictation),
        allowsBareModifier: true,
        allowsMouseButton: true,
        description: "Hold %@ to talk, or tap it to keep listening hands-free."
      )

      if settings.isSecondLanguageEnabled {
        row(
          .secondLanguage,
          title: "Second Language",
          binding: binding(for: .secondLanguage),
          allowsBareModifier: true,
          allowsMouseButton: true,
          description: "Hold %@ to dictate in your other language."
        )
      }

      row(
        .readAloud,
        title: "Read Aloud",
        binding: binding(for: .readAloud),
        allowsBareModifier: false,
        allowsMouseButton: false,
        description: "Press %@ to read the selection, again to stop."
      )

      if let conflictMessage {
        Text(conflictMessage)
          .font(.caption)
          .foregroundStyle(Color.orange)
          .padding(.vertical, 8)
      }
    }
  }

  private func row(
    _ role: Role,
    title: String,
    binding: Binding<KeyBinding>,
    allowsBareModifier: Bool,
    allowsMouseButton: Bool,
    /// A sentence with %@ where the bound keys go, so it renames itself with
    /// the binding.
    description: String
  ) -> some View {
    KeyRecorderView(
      keyBinding: binding,
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
      let describedBinding = keyBinding.isMouseButton
        ? keyBinding.label
        : caps.joined(separator: " ")
      let baseDescription = String(format: description, describedBinding)
      let resolvedDescription = keyBinding.isMouseButton
        ? baseDescription
          + " This button no longer performs its usual action while Talkify is ready."
        : baseDescription
      ShortcutRow(
        caps: caps,
        title: title,
        description: resolvedDescription,
        isRecording: isRecording,
        accent: role.color,
        acceptsMouseButton: allowsMouseButton,
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
    Binding(
      get: { currentBinding(for: role) },
      set: { candidate in
        if let conflict = conflictingRole(for: candidate, excluding: role) {
          conflictMessage = "\(candidate.label) is already used by \(conflict.title)."
          return
        }
        conflictMessage = nil
        switch role {
        case .dictation: settings.dictationTriggerBinding = candidate
        case .secondLanguage: settings.secondaryTriggerBinding = candidate
        case .readAloud: settings.readAloudBinding = candidate
        }
      }
    )
  }

  private func currentBinding(for role: Role) -> KeyBinding {
    switch role {
    case .dictation: settings.dictationTriggerBinding
    case .secondLanguage: settings.secondaryTriggerBinding
    case .readAloud: settings.readAloudBinding
    }
  }

  private func conflictingRole(
    for candidate: KeyBinding,
    excluding role: Role
  ) -> Role? {
    let activeRoles: [Role] = settings.isSecondLanguageEnabled
      ? [.dictation, .secondLanguage, .readAloud]
      : [.dictation, .readAloud]
    return activeRoles.first {
      $0 != role && currentBinding(for: $0).hasSameInputAndModifiers(as: candidate)
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
