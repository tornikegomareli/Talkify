import ApplicationServices

/// Read-only Accessibility access to the focused element's selected text —
/// Read Aloud's entire AX surface. It never inserts, so it stays clear of
/// TextInsertionService's target validation and clipboard machinery.
@MainActor
struct FocusedSelectionReader {
  /// Nil when nothing is focused, the element exposes no selection, or
  /// the selection is empty.
  func selectedText() -> String? {
    let systemWideElement = AXUIElementCreateSystemWide()
    var focused: CFTypeRef?
    guard AXUIElementCopyAttributeValue(
      systemWideElement,
      kAXFocusedUIElementAttribute as CFString,
      &focused
    ) == .success,
    let focused else {
      return nil
    }

    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(
      focused as! AXUIElement,
      kAXSelectedTextAttribute as CFString,
      &value
    ) == .success else {
      return nil
    }

    return value as? String
  }
}
