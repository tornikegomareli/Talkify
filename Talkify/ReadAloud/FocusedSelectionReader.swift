import ApplicationServices

/// Read-only Accessibility access to the focused element's selected text —
/// Read Aloud's entire AX surface. It never inserts, so it stays clear of
/// TextInsertionService's target validation and clipboard machinery.
@MainActor
struct FocusedSelectionReader {
  /// What the focused element is offering. A secure field is its own case
  /// rather than an empty selection: Direct Dictation refuses those and says
  /// so, and Read Aloud speaks into the room, so it has to refuse them too.
  enum Selection: Equatable {
    case text(String)
    case secureField
    case none
  }

  /// What the focused element reports, flattened to plain values so the
  /// decision below can be tested without a live element. Follows the
  /// `TextInsertionService.Dependencies` pattern already used in-tree.
  struct Focus: Equatable {
    var subrole: String?
    var selectedText: String?
  }

  struct Dependencies {
    var focus: @MainActor () -> Focus?

    static let live = Dependencies(focus: Self.readFocus)

    private static func readFocus() -> Focus? {
      let systemWide = AXUIElementCreateSystemWide()
      guard let value = copyAttribute(systemWide, kAXFocusedUIElementAttribute),
         CFGetTypeID(value) == AXUIElementGetTypeID()
      else {
        // The success code says the attribute was read, not that it holds the
        // type its name implies, so the type is checked before the cast.
        return nil
      }
      let element = value as! AXUIElement
      return Focus(
        subrole: copyAttribute(element, kAXSubroleAttribute) as? String,
        selectedText: copyAttribute(element, kAXSelectedTextAttribute) as? String
      )
    }

    private static func copyAttribute(
      _ element: AXUIElement,
      _ attribute: String
    ) -> CFTypeRef? {
      var value: CFTypeRef?
      guard AXUIElementCopyAttributeValue(
        element,
        attribute as CFString,
        &value
      ) == .success else {
        return nil
      }
      return value
    }
  }

  let dependencies: Dependencies

  init(dependencies: Dependencies = .live) {
    self.dependencies = dependencies
  }

  func selection() -> Selection {
    guard let focus = dependencies.focus() else { return .none }
    guard focus.subrole != kAXSecureTextFieldSubrole as String else {
      return .secureField
    }
    guard let text = focus.selectedText,
       !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      return .none
    }
    return .text(text)
  }
}
