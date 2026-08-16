import Carbon
import Foundation

/// The keyboard actually under the user's hands: what shape it is, and what is
/// printed on each key.
///
/// Both halves are needed to draw a keyboard someone recognizes. The shape
/// decides which keys exist and how wide they are — an ISO board has a key
/// between left ⇧ and Z that ANSI does not, and its Return is tall. The legends
/// decide what is written on them, which is where AZERTY, QWERTZ and Georgian
/// diverge from QWERTY while sharing the same keycodes underneath.
struct KeyboardLayout: Equatable {
  enum Shape: Equatable {
    case ansi
    case iso
    case jis
  }

  let shape: Shape
  /// Legends by keycode, empty for a key the layout produces nothing for.
  let legends: [Int64: String]

  /// What is printed on this key, uppercased the way a keycap is.
  func legend(for keyCode: Int64) -> String? {
    legends[keyCode].map { $0.uppercased() }
  }

  static let ansiFallback = KeyboardLayout(shape: .ansi, legends: [:])

  /// Reads the attached keyboard and the selected input source.
  ///
  /// `KBGetLayoutType` answers the shape from the keyboard itself, so it stays
  /// right when someone plugs in an external board. The legends come from the
  /// input source, so they change when the user switches language without any
  /// hardware changing at all.
  static func current() -> KeyboardLayout {
    KeyboardLayout(shape: currentShape(), legends: currentLegends(for: KeyboardMap.legendKeyCodes))
  }

  private static func currentShape() -> Shape {
    switch UInt32(KBGetLayoutType(Int16(LMGetKbdType()))) {
    case UInt32(kKeyboardISO): .iso
    case UInt32(kKeyboardJIS): .jis
    default: .ansi
    }
  }

  private static func currentLegends(for keyCodes: [Int64]) -> [Int64: String] {
    guard
      let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
      let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
    else {
      return [:]
    }

    let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
    let keyboardType = UInt32(LMGetKbdType())
    var legends: [Int64: String] = [:]
    for keyCode in keyCodes {
      if let legend = translate(keyCode: keyCode, data: data, keyboardType: keyboardType) {
        legends[keyCode] = legend
      }
    }
    return legends
  }

  /// `kUCKeyActionDisplay` with dead keys disabled is what asks "what does this
  /// keycap say", rather than "what would typing it produce right now".
  private static func translate(
    keyCode: Int64,
    data: Data,
    keyboardType: UInt32
  ) -> String? {
    var deadKeyState: UInt32 = 0
    var length = 0
    var characters = [UniChar](repeating: 0, count: 4)

    let translated = data.withUnsafeBytes { buffer -> Bool in
      guard let layout = buffer.baseAddress?
        .assumingMemoryBound(to: UCKeyboardLayout.self)
      else {
        return false
      }
      return UCKeyTranslate(
        layout,
        UInt16(keyCode),
        UInt16(kUCKeyActionDisplay),
        0,
        keyboardType,
        OptionBits(kUCKeyTranslateNoDeadKeysBit),
        &deadKeyState,
        characters.count,
        &length,
        &characters
      ) == noErr
    }

    guard translated, length > 0 else { return nil }
    let legend = String(utf16CodeUnits: characters, count: length)
    return legend.trimmingCharacters(in: .whitespaces).isEmpty ? nil : legend
  }

  /// Posted when the user switches input source, so the drawn keyboard can
  /// relabel itself without Settings being reopened.
  static let inputSourceChanged = Notification.Name(
    kTISNotifySelectedKeyboardInputSourceChanged as String
  )
}
