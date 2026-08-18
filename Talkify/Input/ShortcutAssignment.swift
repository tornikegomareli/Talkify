import CoreGraphics

/// Picking a binding by clicking keys on the drawn keyboard.
///
/// Separate from `KeyboardMap`, which is about what to draw: this is about what
/// a sequence of clicks means. Pure, so the picking rules can be asserted
/// without a window — clicking a modifier twice to let it go has no other way
/// of being tested, since it otherwise only exists inside a view.
enum ShortcutAssignment {
  /// The four modifiers a binding can *require*. fn is missing on purpose: a
  /// binding stores its required modifiers as `CGEventFlags` command, option,
  /// control and shift, so fn can only ever be the bound key itself.
  static let combiningModifiers: Set<Int64> = [55, 54, 58, 61, 59, 62, 56, 60]

  /// What a click does. A modifier waits for the rest of the combination;
  /// anything else finishes it.
  enum Click: Equatable {
    /// Keep collecting, with this as the new selection.
    case picking([Int64])
    /// The selection is complete.
    case complete([Int64])
  }

  static func click(_ keyCode: Int64, picked: [Int64]) -> Click {
    guard combiningModifiers.contains(keyCode) else {
      return .complete(picked + [keyCode])
    }
    // Clicking a held modifier again lets it go, so a mis-click is undoable
    // without starting the whole selection over.
    guard let index = picked.firstIndex(of: keyCode) else {
      return .picking(picked + [keyCode])
    }
    var remaining = picked
    remaining.remove(at: index)
    return .picking(remaining)
  }

  /// Builds a binding from keys clicked on the drawn keyboard, in click order.
  ///
  /// The bound key is the first thing clicked that is not one of the four
  /// combining modifiers — fn, a letter, Escape — and everything else becomes a
  /// required modifier. When only combining modifiers were clicked, the last
  /// one is the key, which is how a bare ⌥ gets bound.
  ///
  /// This is what lets someone assign a combination they cannot type into the
  /// recorder, because the system or another app swallows it first.
  static func binding(forClicked clicked: [Int64], layout: KeyboardLayout) -> KeyBinding? {
    guard let last = clicked.last else { return nil }
    let keyCode = clicked.first { !combiningModifiers.contains($0) } ?? last

    var flags: CGEventFlags = []
    for modifier in clicked where modifier != keyCode {
      flags.insert(KeyBinding.modifierMask(forKeyCode: modifier))
    }
    // fn cannot be a required modifier, only a bound key.
    flags.remove(.maskSecondaryFn)

    let isModifierKey = KeyBinding.modifierKeyName(forKeyCode: keyCode) != nil
    var binding = KeyBinding(
      keyCode: keyCode,
      modifierFlags: flags.rawValue,
      isModifierKey: isModifierKey,
      label: "",
      keyEquivalent: isModifierKey ? "" : (layout.legend(for: keyCode)?.lowercased() ?? "")
    )
    // The label is the caps this same binding draws, so it needs the binding
    // before it can be written.
    binding.label = KeyboardMap.caps(for: binding, layout: layout).joined(separator: " ")
    return binding
  }
}
