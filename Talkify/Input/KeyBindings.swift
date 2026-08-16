import AppKit

/// One recorded key binding: a keycode plus required modifiers, with the
/// display strings captured at record time (System Settings-style recording
/// in the Shortcuts section). Codable — AppSettings persists it as JSON.
struct KeyBinding: Equatable, Codable {
  /// CGEvent keycode of the bound key.
  var keyCode: Int64
  /// Required modifier flags, `CGEventFlags` raw value filtered to
  /// command/option/control/shift.
  var modifierFlags: UInt64
  /// True when the bound key is itself a modifier (fn, ⌘, ⌥ …): the event
  /// tap watches flagsChanged for it instead of keyDown/keyUp, which is
  /// what makes hold-and-release gestures work on it.
  var isModifierKey: Bool
  /// Human-readable label ("fn", "⌥ ⎋", "F5"), shown in Settings and the
  /// status menu.
  var label: String
  /// Menu key-equivalent character; empty when not representable (bare
  /// modifiers) — the menu falls back to a badge then.
  var keyEquivalent: String

  var modifiers: CGEventFlags { CGEventFlags(rawValue: modifierFlags) }

  var cocoaModifiers: NSEvent.ModifierFlags {
    var flags: NSEvent.ModifierFlags = []
    if modifiers.contains(.maskCommand) { flags.insert(.command) }
    if modifiers.contains(.maskAlternate) { flags.insert(.option) }
    if modifiers.contains(.maskControl) { flags.insert(.control) }
    if modifiers.contains(.maskShift) { flags.insert(.shift) }
    return flags
  }

  /// The flag bit a modifier-key binding toggles in flagsChanged events.
  var modifierKeyMask: CGEventFlags {
    Self.modifierMask(forKeyCode: keyCode)
  }

  static let fnTrigger = KeyBinding(
    keyCode: 63, modifierFlags: 0, isModifierKey: true,
    label: "fn", keyEquivalent: ""
  )

  /// Default second-language trigger: right ⌥ held, mirroring the fn hold
  /// on the other side of the keyboard. Only ever installed once a second
  /// language is chosen, so it costs nothing until then.
  static let rightOptionTrigger = KeyBinding(
    keyCode: 61, modifierFlags: 0, isModifierKey: true,
    label: "right ⌥", keyEquivalent: ""
  )

  static let optionEscape = KeyBinding(
    keyCode: 53, modifierFlags: CGEventFlags.maskAlternate.rawValue,
    isModifierKey: false, label: "⌥ ⎋", keyEquivalent: "\u{1B}"
  )

  /// Which physical key a side-specific modifier binding watches, and the pair
  /// it belongs to.
  ///
  /// `CGEventFlags` collapses left and right into one bit: releasing right ⌥
  /// while left ⌥ is held leaves `.maskAlternate` set, so a trigger bound to
  /// right ⌥ would never see its release and the session would stay open. The
  /// low 16 bits carry per-key state (`NX_DEVICE*KEYMASK` in IOKit's
  /// `IOLLEvent.h`), which does distinguish them.
  ///
  /// `pair` exists to tell "both keys are up" apart from "this keyboard does
  /// not report device bits at all", so the monitor can fall back safely.
  static func deviceMasks(forKeyCode keyCode: Int64) -> (own: UInt64, pair: UInt64)? {
    switch keyCode {
    case 55: (own: 0x0000_0008, pair: 0x0000_0018)  // left ⌘
    case 54: (own: 0x0000_0010, pair: 0x0000_0018)  // right ⌘
    case 58: (own: 0x0000_0020, pair: 0x0000_0060)  // left ⌥
    case 61: (own: 0x0000_0040, pair: 0x0000_0060)  // right ⌥
    case 59: (own: 0x0000_0001, pair: 0x0000_2001)  // left ⌃
    case 62: (own: 0x0000_2000, pair: 0x0000_2001)  // right ⌃
    case 56: (own: 0x0000_0002, pair: 0x0000_0006)  // left ⇧
    case 60: (own: 0x0000_0004, pair: 0x0000_0006)  // right ⇧
    // fn has no left/right twin, so its shared flag is already unambiguous.
    default: nil
    }
  }

  static func modifierMask(forKeyCode keyCode: Int64) -> CGEventFlags {
    switch keyCode {
    case 63: .maskSecondaryFn
    case 54, 55: .maskCommand
    case 58, 61: .maskAlternate
    case 59, 62: .maskControl
    case 56, 60: .maskShift
    default: []
    }
  }

  /// What this key contributes to `NSEvent.ModifierFlags`, so a recorder can
  /// subtract it and keep only the modifiers held alongside it. fn contributes
  /// nothing here: it is not one of the four combining modifiers.
  static func cocoaModifier(forKeyCode keyCode: Int64) -> NSEvent.ModifierFlags {
    switch keyCode {
    case 54, 55: .command
    case 58, 61: .option
    case 59, 62: .control
    case 56, 60: .shift
    default: []
    }
  }

  /// Which of two modifier presses is the bound key while a chord is being
  /// recorded. fn and anything that is not one of the four combining modifiers
  /// outrank them, because only those four can be *required* by a binding —
  /// otherwise pressing fn and adding ⌥ would rebind to a bare ⌥.
  static func chordKey(existing: Int64?, pressed: Int64) -> Int64 {
    guard let existing else { return pressed }
    let existingCombines = cocoaModifier(forKeyCode: existing) != []
    let pressedCombines = cocoaModifier(forKeyCode: pressed) != []
    if existingCombines, !pressedCombines { return pressed }
    if !existingCombines, pressedCombines { return existing }
    return pressed
  }

  static func modifierKeyName(forKeyCode keyCode: Int64) -> String? {
    switch keyCode {
    case 63: "fn"
    case 55: "⌘"
    case 54: "right ⌘"
    case 58: "⌥"
    case 61: "right ⌥"
    case 59: "⌃"
    case 62: "right ⌃"
    case 56: "⇧"
    case 60: "right ⇧"
    default: nil
    }
  }

  /// Display name for a non-modifier key, from the recording event.
  static func keyName(keyCode: UInt16, event: NSEvent?) -> String {
    let special: [UInt16: String] = [
      53: "⎋", 49: "Space", 36: "↩", 48: "⇥", 51: "⌫", 117: "⌦",
      123: "←", 124: "→", 125: "↓", 126: "↑",
      122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
      98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11",
      111: "F12", 105: "F13", 107: "F14", 113: "F15",
    ]
    if let name = special[keyCode] { return name }
    if let chars = event?.charactersIgnoringModifiers, !chars.isEmpty {
      return chars.uppercased()
    }
    return "Key \(keyCode)"
  }

  /// Menu key-equivalent for a non-modifier key; empty when the key has no
  /// sensible menu glyph.
  static func menuKeyEquivalent(keyCode: UInt16, event: NSEvent?) -> String {
    let functionKeys: [UInt16: Int] = [
      122: 1, 120: 2, 99: 3, 118: 4, 96: 5, 97: 6, 98: 7, 100: 8,
      101: 9, 109: 10, 103: 11, 111: 12, 105: 13, 107: 14, 113: 15,
    ]
    if keyCode == 53 { return "\u{1B}" }
    if let n = functionKeys[keyCode],
     let scalar = UnicodeScalar(NSF1FunctionKey + n - 1) {
      return String(scalar)
    }
    if let chars = event?.charactersIgnoringModifiers, chars.count == 1,
     let first = chars.unicodeScalars.first, first.value >= 0x20 {
      return chars.lowercased()
    }
    return ""
  }

  static func modifierSymbols(_ flags: NSEvent.ModifierFlags) -> String {
    var symbols = ""
    if flags.contains(.control) { symbols += "⌃" }
    if flags.contains(.option) { symbols += "⌥" }
    if flags.contains(.shift) { symbols += "⇧" }
    if flags.contains(.command) { symbols += "⌘" }
    return symbols
  }

  static func cgFlags(from flags: NSEvent.ModifierFlags) -> CGEventFlags {
    var cg: CGEventFlags = []
    if flags.contains(.command) { cg.insert(.maskCommand) }
    if flags.contains(.option) { cg.insert(.maskAlternate) }
    if flags.contains(.control) { cg.insert(.maskControl) }
    if flags.contains(.shift) { cg.insert(.maskShift) }
    return cg
  }
}
