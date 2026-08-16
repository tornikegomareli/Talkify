import CoreGraphics

/// The rows of keys to draw, for a given keyboard shape.
///
/// Pure data so the shapes can be compared without a window: the difference
/// between ANSI and ISO is which keycodes appear where, and that is exactly
/// what is easy to get wrong and easy to test.
enum KeyboardMap {
  /// One drawn keycap. `width` is in key units, where 1 is a letter key.
  struct Key: Equatable {
    let keyCode: Int64
    /// A fixed glyph for keys whose cap never changes with the input source
    /// (⇧, ⌘, esc). Keys with no glyph take their legend from the layout.
    let glyph: String?
    var width: CGFloat = 1

    init(_ keyCode: Int64, _ glyph: String? = nil, width: CGFloat = 1) {
      self.keyCode = keyCode
      self.glyph = glyph
      self.width = width
    }
  }

  /// Keycodes whose cap comes from the input source rather than a fixed glyph.
  /// Derived from the rows so the two can never drift apart.
  static let legendKeyCodes: [Int64] = {
    var codes: Set<Int64> = []
    for shape in [KeyboardLayout.Shape.ansi, .iso, .jis] {
      for row in rows(for: shape) {
        for key in row where key.glyph == nil {
          codes.insert(key.keyCode)
        }
      }
    }
    return Array(codes)
  }()

  static func rows(for shape: KeyboardLayout.Shape) -> [[Key]] {
    [functionRow, numberRow(shape), upperRow(shape), homeRow(shape), lowerRow(shape), bottomRow]
  }

  private static let functionRow: [Key] = [
    Key(53, "esc", width: 1.4),
    Key(122, "F1"), Key(120, "F2"), Key(99, "F3"), Key(118, "F4"),
    Key(96, "F5"), Key(97, "F6"), Key(98, "F7"), Key(100, "F8"),
    Key(101, "F9"), Key(109, "F10"), Key(103, "F11"), Key(111, "F12"),
  ]

  /// ISO puts § where ANSI puts the backtick, and moves the backtick down
  /// beside left ⇧ — the most visible difference between the two boards.
  private static func numberRow(_ shape: KeyboardLayout.Shape) -> [Key] {
    let first = Key(shape == .ansi ? 50 : 10)
    return [first]
      + [18, 19, 20, 21, 23, 22, 26, 28, 25, 29, 27, 24].map { Key($0) }
      + [Key(51, "⌫", width: 1.5)]
  }

  /// On ANSI the backslash ends this row. On ISO that key moves to the home
  /// row and Return takes its place, running down through both rows.
  private static func upperRow(_ shape: KeyboardLayout.Shape) -> [Key] {
    let letters = [12, 13, 14, 15, 17, 16, 32, 34, 31, 35, 33, 30].map { Key($0) }
    let tail = shape == .ansi ? [Key(42, width: 1.5)] : [Key(36, "↩", width: 1.25)]
    return [Key(48, "⇥", width: 1.5)] + letters + tail
  }

  private static func homeRow(_ shape: KeyboardLayout.Shape) -> [Key] {
    let letters = [0, 1, 2, 3, 5, 4, 38, 40, 37, 41, 39].map { Key($0) }
    let tail = shape == .ansi
      ? [Key(36, "↩", width: 1.75)]
      : [Key(42), Key(36, "↩", width: 1.25)]
    return [Key(57, "caps", width: 1.75)] + letters + tail
  }

  private static func lowerRow(_ shape: KeyboardLayout.Shape) -> [Key] {
    let letters = [6, 7, 8, 9, 11, 45, 46, 43, 47, 44].map { Key($0) }
    let head = shape == .ansi
      ? [Key(56, "⇧", width: 2.25)]
      : [Key(56, "⇧", width: 1.25), Key(50)]
    return head + letters + [Key(60, "⇧", width: 2.25)]
  }

  private static let bottomRow: [Key] = [
    Key(63, "fn"), Key(59, "⌃"), Key(58, "⌥"), Key(55, "⌘", width: 1.25),
    Key(49, "", width: 5),
    Key(54, "⌘", width: 1.25), Key(61, "⌥"),
    Key(123, "←"), Key(126, "↑"), Key(125, "↓"), Key(124, "→"),
  ]

  /// Fixed glyphs by keycode, for the caps an input source cannot relabel.
  private static let glyphs: [Int64: String] = [
    53: "esc", 51: "⌫", 48: "⇥", 57: "caps", 36: "↩", 49: "space",
    56: "⇧", 60: "⇧", 63: "fn", 59: "⌃", 62: "⌃", 58: "⌥", 61: "⌥",
    55: "⌘", 54: "⌘", 123: "←", 126: "↑", 125: "↓", 124: "→",
    122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
    98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
  ]

  /// The keycaps a binding shows: its modifiers in the order macOS writes them,
  /// then the key itself. One cap per physical key, rather than one label with
  /// everything crammed into it.
  static func caps(for binding: KeyBinding, layout: KeyboardLayout) -> [String] {
    var caps: [String] = []
    let modifiers = binding.modifiers
    if modifiers.contains(.maskControl) { caps.append("⌃") }
    if modifiers.contains(.maskAlternate) { caps.append("⌥") }
    if modifiers.contains(.maskShift) { caps.append("⇧") }
    if modifiers.contains(.maskCommand) { caps.append("⌘") }
    caps.append(cap(for: binding.keyCode, layout: layout))
    return caps
  }

  /// A modifier reads as its own glyph rather than "right ⌥" — a cap has no
  /// room for a side, and the drawn keyboard already shows which one is lit.
  private static func cap(for keyCode: Int64, layout: KeyboardLayout) -> String {
    if let glyph = glyphs[keyCode] { return glyph }
    if let legend = layout.legend(for: keyCode) { return legend }
    return "?"
  }

  /// The keys a binding lights up: its own key plus whichever modifier keys it
  /// requires. A modifier appears on both sides of the board, so both light —
  /// the binding does not care which one is pressed unless it named a side.
  static func highlighted(for binding: KeyBinding) -> Set<Int64> {
    var keyCodes: Set<Int64> = [binding.keyCode]
    let modifiers = binding.modifiers
    if modifiers.contains(.maskCommand) { keyCodes.formUnion([55, 54]) }
    if modifiers.contains(.maskAlternate) { keyCodes.formUnion([58, 61]) }
    if modifiers.contains(.maskControl) { keyCodes.formUnion([59, 62]) }
    if modifiers.contains(.maskShift) { keyCodes.formUnion([56, 60]) }
    return keyCodes
  }
}
