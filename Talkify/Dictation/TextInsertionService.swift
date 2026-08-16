import AppKit
import ApplicationServices

@MainActor
final class TextInsertionService {
  /// How finalized text reaches the target app. Paste is the default;
  /// typing exists for editors that refuse synthetic ⌘V — terminals,
  /// virtual machines, apps with custom paste handling.
  enum InsertionMethod: String, CaseIterable, Hashable {
    case paste
    case typing
  }

  struct Target {
    fileprivate let element: AXUIElement?
    fileprivate let processIdentifier: pid_t

    let isSecure: Bool
    let displayID: CGDirectDisplayID?

    init(
      element: AXUIElement?,
      processIdentifier: pid_t,
      isSecure: Bool,
      displayID: CGDirectDisplayID?
    ) {
      self.element = element
      self.processIdentifier = processIdentifier
      self.isSecure = isSecure
      self.displayID = displayID
    }
  }

  struct Dependencies {
    let pasteboard: NSPasteboard
    let focusedElement: @MainActor () -> AXUIElement?
    let frontmostApplication: @MainActor () -> NSRunningApplication?
    let isProcessRunning: @MainActor (pid_t) -> Bool
    let isTargetFocused: @MainActor (Target) -> Bool
    let postPasteShortcut: @MainActor () -> Bool
    let postTypingText: @MainActor (String) -> Bool
    let waitForPasteRead: @MainActor () async -> Void

    static var live: Self {
      Self(
        pasteboard: .general,
        focusedElement: TextInsertionService.focusedElement,
        frontmostApplication: { NSWorkspace.shared.frontmostApplication },
        isProcessRunning: { processIdentifier in
          guard let application = NSRunningApplication(
            processIdentifier: processIdentifier
          ) else {
            return false
          }
          return !application.isTerminated
        },
        isTargetFocused: TextInsertionService.isStillFocused,
        postPasteShortcut: TextInsertionService.postPasteShortcut,
        postTypingText: TextInsertionService.postTypingText,
        waitForPasteRead: {
          try? await Task.sleep(for: .milliseconds(500))
        }
      )
    }
  }

  private let dependencies: Dependencies

  init(dependencies: Dependencies = .live) {
    self.dependencies = dependencies
  }

  func captureFocusedTarget() -> Target? {
    if let element = dependencies.focusedElement() {
      var processIdentifier: pid_t = 0
      AXUIElementGetPid(element, &processIdentifier)

      return Target(
        element: element,
        processIdentifier: processIdentifier,
        isSecure: isSecureTextField(element),
        displayID: displayID(for: element)
      )
    }

    // Some apps expose no focused AX element even while an editor has focus.
    // Keep the application as the safest available focus boundary.
    guard let application = dependencies.frontmostApplication() else { return nil }
    return Target(
      element: nil,
      processIdentifier: application.processIdentifier,
      isSecure: false,
      displayID: nil
    )
  }

  func insert(_ text: String, into target: Target?, method: InsertionMethod = .paste) async {
    guard !text.isEmpty else { return }
    guard let target else {
      copyToClipboard(text)
      return
    }

    guard dependencies.isProcessRunning(target.processIdentifier) else {
      copyToClipboard(text)
      return
    }

    guard dependencies.isTargetFocused(target) else {
      copyToClipboard(text)
      return
    }
    switch method {
    case .paste:
      await pasteAndRestoreClipboard(text, into: target)
    case .typing:
      typeText(text, into: target)
    }
  }

  /// Typing skips the clipboard entirely: the events land wherever the
  /// keyboard would, which is the whole point for apps that refuse pasted
  /// text. A target that slipped away mid-session still gets nothing typed.
  private func typeText(_ text: String, into target: Target) {
    guard dependencies.isTargetFocused(target),
       dependencies.postTypingText(text) else {
      copyToClipboard(text)
      return
    }
  }

  private static func focusedElement() -> AXUIElement? {
    let systemWideElement = AXUIElementCreateSystemWide()
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(
      systemWideElement,
      kAXFocusedUIElementAttribute as CFString,
      &value
    ) == .success,
    let value else {
      return nil
    }
    return (value as! AXUIElement)
  }

  private func isSecureTextField(_ element: AXUIElement) -> Bool {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(
      element,
      kAXSubroleAttribute as CFString,
      &value
    ) == .success else {
      return false
    }

    return value as? String == kAXSecureTextFieldSubrole as String
  }

  private func displayID(for element: AXUIElement) -> CGDirectDisplayID? {
    let frameElement = window(for: element) ?? element
    guard let frame = frame(of: frameElement) else { return nil }

    let displays = NSScreen.screens.compactMap { screen -> (CGDirectDisplayID, CGRect)? in
      guard let displayID = screen.cgDirectDisplayID else { return nil }
      return (displayID, CGDisplayBounds(displayID))
    }

    let center = CGPoint(x: frame.midX, y: frame.midY)
    if let containingDisplay = displays.first(where: { $0.1.contains(center) }) {
      return containingDisplay.0
    }

    return displays.max { lhs, rhs in
      lhs.1.intersection(frame).area < rhs.1.intersection(frame).area
    }?.0
  }

  private func window(for element: AXUIElement) -> AXUIElement? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(
      element,
      kAXWindowAttribute as CFString,
      &value
    ) == .success,
    let value else {
      return nil
    }

    return (value as! AXUIElement)
  }

  private func frame(of element: AXUIElement) -> CGRect? {
    var positionValue: CFTypeRef?
    var sizeValue: CFTypeRef?

    guard AXUIElementCopyAttributeValue(
      element,
      kAXPositionAttribute as CFString,
      &positionValue
    ) == .success,
    AXUIElementCopyAttributeValue(
      element,
      kAXSizeAttribute as CFString,
      &sizeValue
    ) == .success,
    let positionValue,
    let sizeValue,
    CFGetTypeID(positionValue) == AXValueGetTypeID(),
    CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
      return nil
    }

    var position = CGPoint.zero
    var size = CGSize.zero
    guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
       AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else {
      return nil
    }

    return CGRect(origin: position, size: size)
  }

  private static func isStillFocused(_ target: Target) -> Bool {
    guard let targetElement = target.element else {
      return NSWorkspace.shared.frontmostApplication?.processIdentifier
        == target.processIdentifier
    }

    let systemWideElement = AXUIElementCreateSystemWide()
    var value: CFTypeRef?

    guard AXUIElementCopyAttributeValue(
      systemWideElement,
      kAXFocusedUIElementAttribute as CFString,
      &value
    ) == .success,
    let value else {
      return false
    }

    return CFEqual(value, targetElement)
  }

  private func pasteAndRestoreClipboard(_ text: String, into target: Target) async {
    let pasteboard = dependencies.pasteboard
    let sourceItems = pasteboard.pasteboardItems ?? []
    var savedItems: [NSPasteboardItem] = []
    savedItems.reserveCapacity(sourceItems.count)

    for sourceItem in sourceItems {
      let savedItem = NSPasteboardItem()
      for type in sourceItem.types {
        if let data = sourceItem.data(forType: type) {
          savedItem.setData(data, forType: type)
        }
      }
      savedItems.append(savedItem)
    }

    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
    let insertedChangeCount = pasteboard.changeCount

    guard dependencies.isTargetFocused(target),
       dependencies.postPasteShortcut() else { return }
    await dependencies.waitForPasteRead()

    // Reads do not change changeCount. The delay gives asynchronous editors
    // time to read; this guard protects newer clipboard contents.
    guard pasteboard.changeCount == insertedChangeCount else { return }
    pasteboard.clearContents()
    if !savedItems.isEmpty {
      pasteboard.writeObjects(savedItems)
    }
  }

  private func copyToClipboard(_ text: String) {
    let pasteboard = dependencies.pasteboard
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
  }

  private static func postPasteShortcut() -> Bool {
    guard let source = CGEventSource(stateID: .combinedSessionState),
       let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
       let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
      return false
    }

    keyDown.flags = .maskCommand
    keyUp.flags = .maskCommand
    keyDown.post(tap: .cghidEventTap)
    keyUp.post(tap: .cghidEventTap)
    return true
  }

  /// Delivers text as Unicode keyboard events. The HID event carries a
  /// string rather than real keycodes, so it types into any editor that
  /// accepts a keyboard — including ones that reject synthetic ⌘V.
  private static func postTypingText(_ text: String) -> Bool {
    guard let source = CGEventSource(stateID: .combinedSessionState) else {
      return false
    }

    // Apps read only a few tens of characters per event before truncating,
    // so the transcript goes out in chunks split on grapheme boundaries.
    var start = text.startIndex
    while start < text.endIndex {
      let end = text.index(start, offsetBy: 20, limitedBy: text.endIndex) ?? text.endIndex
      guard postTypingChunk(String(text[start..<end]), source: source) else {
        return false
      }
      start = end
    }
    return true
  }

  private static func postTypingChunk(_ chunk: String, source: CGEventSource) -> Bool {
    let characters = Array(chunk.utf16)
    guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
       let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
      return false
    }

    characters.withUnsafeBufferPointer { buffer in
      keyDown.keyboardSetUnicodeString(
        stringLength: characters.count,
        unicodeString: buffer.baseAddress
      )
      keyUp.keyboardSetUnicodeString(
        stringLength: characters.count,
        unicodeString: buffer.baseAddress
      )
    }

    keyDown.post(tap: .cghidEventTap)
    keyUp.post(tap: .cghidEventTap)
    return true
  }
}

private extension CGRect {
  var area: CGFloat {
    guard !isNull else { return 0 }
    return width * height
  }
}
