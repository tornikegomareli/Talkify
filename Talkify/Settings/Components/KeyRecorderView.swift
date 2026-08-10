import AppKit
import SwiftUI

/// System Settings-style key recorder: click to arm, and the next key press
/// becomes the binding. While armed, a local event monitor swallows the
/// keystroke and `onRecordingChanged` pauses the global trigger tap so the
/// rebind cannot start a dictation session. Plain Escape cancels recording.
///
/// `capturesSingleKey` is the Dictation Trigger mode: a lone key — including
/// a bare modifier like fn or right ⌘ — becomes the hold/tap trigger, and
/// held modifiers are ignored. Otherwise a full combo (modifiers + key) is
/// captured, the shape a toggle shortcut needs.
struct KeyRecorderView: View {
  @Binding var binding: KeyBinding
  let capturesSingleKey: Bool
  let onRecordingChanged: (Bool) -> Void

  @Environment(\.colorSchemeContrast) private var contrast
  @State private var isRecording = false
  @State private var monitor: Any?

  var body: some View {
    Button {
      isRecording ? cancelRecording() : startRecording()
    } label: {
      Text(isRecording ? "Press keys…" : binding.label)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(isRecording ? SettingsTheme.accent : .white)
        .frame(minWidth: 96)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
          .white.opacity(isRecording ? 0.14 : 0.08),
          in: Capsule()
        )
        .overlay {
          Capsule().stroke(
            isRecording
              ? SettingsTheme.accent.opacity(0.7)
              : .white.opacity(contrast == .increased ? 0.3 : 0.12),
            lineWidth: 1
          )
        }
    }
    .buttonStyle(.plain)
    .onDisappear {
      cancelRecording()
    }
  }

  private func startRecording() {
    isRecording = true
    onRecordingChanged(true)
    monitor = NSEvent.addLocalMonitorForEvents(
      matching: [.keyDown, .flagsChanged]
    ) { event in
      handle(event)
      return nil
    }
  }

  private func cancelRecording() {
    if let monitor {
      NSEvent.removeMonitor(monitor)
    }
    monitor = nil
    if isRecording {
      isRecording = false
      onRecordingChanged(false)
    }
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
      let modifiers = capturesSingleKey
        ? NSEvent.ModifierFlags()
        : event.modifierFlags.intersection([.command, .option, .control, .shift])
      let keyName = KeyBinding.keyName(keyCode: event.keyCode, event: event)
      let symbols = KeyBinding.modifierSymbols(modifiers)
      binding = KeyBinding(
        keyCode: Int64(event.keyCode),
        modifierFlags: KeyBinding.cgFlags(from: modifiers).rawValue,
        isModifierKey: false,
        label: symbols.isEmpty ? keyName : "\(symbols) \(keyName)",
        keyEquivalent: KeyBinding.menuKeyEquivalent(keyCode: event.keyCode, event: event)
      )
      cancelRecording()

    case .flagsChanged:
      // Single-key mode only: a lone modifier press is a valid
      // trigger. Presses show the flag; releases are ignored.
      guard capturesSingleKey,
         let name = KeyBinding.modifierKeyName(forKeyCode: Int64(event.keyCode)),
         !KeyBinding.modifierMask(forKeyCode: Int64(event.keyCode)).isEmpty
      else { return }
      let mask = KeyBinding.modifierMask(forKeyCode: Int64(event.keyCode))
      let cgFlags = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
      guard cgFlags.contains(mask) || event.modifierFlags.contains(.function) else { return }
      binding = KeyBinding(
        keyCode: Int64(event.keyCode),
        modifierFlags: 0,
        isModifierKey: true,
        label: name,
        keyEquivalent: ""
      )
      cancelRecording()

    default:
      break
    }
  }
}
