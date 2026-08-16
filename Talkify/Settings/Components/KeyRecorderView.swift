import AppKit
import SwiftUI

/// System Settings-style key recorder: click to arm, and the next key press
/// becomes the binding. While armed, a local event monitor swallows the
/// keystroke and `onRecordingChanged` pauses the global trigger tap so the
/// rebind cannot start a dictation session. Plain Escape cancels recording.
///
/// `allowsBareModifier` is the Dictation Trigger mode: a bare modifier like fn
/// or right ⌘ can be the bound key, so a hold-and-release gesture has something
/// to hold. Both modes record whatever modifiers are held alongside it.
struct KeyRecorderView<Label: View>: View {
  @Binding var keyBinding: KeyBinding
  let allowsBareModifier: Bool
  /// Owned by the caller so only one recorder is ever armed, and so a click on
  /// the drawn keyboard can finish a binding and disarm this at the same time.
  @Binding var isRecording: Bool
  let onRecordingChanged: (Bool) -> Void
  /// What the control looks like, given the current binding and whether it is
  /// armed. Swappable so a whole row can be the recorder, not just a capsule.
  @ViewBuilder let label: (KeyBinding, Bool) -> Label

  @State private var monitor: Any?
  /// The modifier chord built so far, committed when the first key comes up.
  @State private var chord: KeyBinding?

  var body: some View {
    Button {
      isRecording.toggle()
    } label: {
      label(keyBinding, isRecording)
    }
    .buttonStyle(.plain)
    .onChange(of: isRecording) { _, armed in
      armed ? startMonitor() : stopMonitor()
      onRecordingChanged(armed)
    }
    .onDisappear {
      // Torn down here rather than through the binding: `onChange` is not
      // guaranteed to run for a view being removed, and a monitor that outlives
      // its view swallows every keystroke in the window for good.
      stopMonitor()
      if isRecording {
        isRecording = false
        onRecordingChanged(false)
      }
    }
  }

  private func startMonitor() {
    guard monitor == nil else { return }
    monitor = NSEvent.addLocalMonitorForEvents(
      matching: [.keyDown, .flagsChanged]
    ) { event in
      handle(event)
      return nil
    }
  }

  private func stopMonitor() {
    if let monitor {
      NSEvent.removeMonitor(monitor)
    }
    monitor = nil
    chord = nil
  }

  private func cancelRecording() {
    isRecording = false
  }

  private func handle(_ event: NSEvent) {
    switch event.type {
    case .keyDown:
      // Plain Escape cancels; anything else records.
      if event.keyCode == 53,
       event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
        cancelRecording()
        return
      }
      let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
      let keyName = KeyBinding.keyName(keyCode: event.keyCode, event: event)
      let symbols = KeyBinding.modifierSymbols(modifiers)
      keyBinding = KeyBinding(
        keyCode: Int64(event.keyCode),
        modifierFlags: KeyBinding.cgFlags(from: modifiers).rawValue,
        isModifierKey: false,
        label: symbols.isEmpty ? keyName : "\(symbols) \(keyName)",
        keyEquivalent: KeyBinding.menuKeyEquivalent(keyCode: event.keyCode, event: event)
      )
      cancelRecording()

    case .flagsChanged:
      // Trigger mode only: a modifier can be the bound key here, on its own or
      // with others held. The chord is committed on the first release rather
      // than on each press, so reaching fn + ⌥ is not cut short by ⌥ landing
      // first.
      guard allowsBareModifier,
         let name = KeyBinding.modifierKeyName(forKeyCode: Int64(event.keyCode)),
         !KeyBinding.modifierMask(forKeyCode: Int64(event.keyCode)).isEmpty
      else { return }

      let mask = KeyBinding.modifierMask(forKeyCode: Int64(event.keyCode))
      let cgFlags = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
      let isPress = cgFlags.contains(mask) || event.modifierFlags.contains(.function)
      guard isPress else {
        if let chord { keyBinding = chord }
        cancelRecording()
        return
      }

      // fn outranks a plain modifier, so pressing fn and then adding ⌥ keeps
      // fn as the key instead of rebinding to a bare ⌥.
      let keyCode = KeyBinding.chordKey(existing: chord?.keyCode, pressed: Int64(event.keyCode))
      // Everything held except what the bound key itself contributes.
      let others = event.modifierFlags
        .intersection([.command, .option, .control, .shift])
        .subtracting(KeyBinding.cocoaModifier(forKeyCode: keyCode))
      let symbols = KeyBinding.modifierSymbols(others)
      let keyName = KeyBinding.modifierKeyName(forKeyCode: keyCode) ?? name
      chord = KeyBinding(
        keyCode: keyCode,
        modifierFlags: KeyBinding.cgFlags(from: others).rawValue,
        isModifierKey: true,
        label: symbols.isEmpty ? keyName : "\(symbols) \(keyName)",
        keyEquivalent: ""
      )

    default:
      break
    }
  }
}

/// The default control: a capsule showing the binding, or "Press keys…" while
/// armed.
struct KeyRecorderCapsule: View {
  let title: String
  let isRecording: Bool

  @Environment(\.colorSchemeContrast) private var contrast

  var body: some View {
    Text(isRecording ? "Press keys…" : title)
      .font(.system(size: 12, weight: .semibold))
      .foregroundStyle(isRecording ? SettingsTheme.accent : .white)
      .frame(minWidth: 96)
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(.white.opacity(isRecording ? 0.14 : 0.08), in: Capsule())
      .overlay {
        Capsule().stroke(
          isRecording
            ? SettingsTheme.accent.opacity(0.7)
            : .white.opacity(contrast == .increased ? 0.3 : 0.12),
          lineWidth: 1
        )
      }
  }
}

extension KeyRecorderView where Label == KeyRecorderCapsule {
  init(
    keyBinding: Binding<KeyBinding>,
    isRecording: Binding<Bool>,
    allowsBareModifier: Bool,
    onRecordingChanged: @escaping (Bool) -> Void
  ) {
    self.init(
      keyBinding: keyBinding,
      allowsBareModifier: allowsBareModifier,
      isRecording: isRecording,
      onRecordingChanged: onRecordingChanged
    ) { binding, armed in
      KeyRecorderCapsule(title: binding.label, isRecording: armed)
    }
  }
}
