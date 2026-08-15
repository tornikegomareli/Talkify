import AppKit
import ApplicationServices

@MainActor
final class TextInsertionService {
  struct Target {
    fileprivate let element: AXUIElement
    fileprivate let processIdentifier: pid_t
    fileprivate let bundleIdentifier: String?

    let isSecure: Bool
    let displayID: CGDirectDisplayID?
  }

  private enum Route {
    case accessibility
    case paste
  }

  private var routesByBundleIdentifier: [String: Route] = [:]

  func captureFocusedTarget() -> Target? {
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

    let element = value as! AXUIElement
    var processIdentifier: pid_t = 0
    AXUIElementGetPid(element, &processIdentifier)

    let application = NSRunningApplication(processIdentifier: processIdentifier)
    return Target(
      element: element,
      processIdentifier: processIdentifier,
      bundleIdentifier: application?.bundleIdentifier,
      isSecure: isSecureTextField(element),
      displayID: displayID(for: element)
    )
  }

  func insert(_ text: String, into target: Target?) async {
    guard !text.isEmpty else { return }
    guard let target else {
      copyToClipboard(text)
      return
    }

    guard let application = NSRunningApplication(
      processIdentifier: target.processIdentifier
    ), !application.isTerminated else {
      copyToClipboard(text)
      return
    }

    let route = target.bundleIdentifier.flatMap { routesByBundleIdentifier[$0] }
    if route != .paste,
       !Self.prefersPaste(bundleIdentifier: target.bundleIdentifier),
       insertThroughAccessibility(text, target: target) {
      remember(.accessibility, for: target.bundleIdentifier)
      return
    }

    remember(.paste, for: target.bundleIdentifier)
    guard isStillFocused(target) else {
      copyToClipboard(text)
      return
    }
    await pasteAndRestoreClipboard(text)
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

  private func insertThroughAccessibility(_ text: String, target: Target) -> Bool {
    var isSettable: DarwinBoolean = false
    let settableResult = AXUIElementIsAttributeSettable(
      target.element,
      kAXSelectedTextAttribute as CFString,
      &isSettable
    )

    guard settableResult == .success, isSettable.boolValue else { return false }

    return AXUIElementSetAttributeValue(
      target.element,
      kAXSelectedTextAttribute as CFString,
      text as CFString
    ) == .success
  }

  nonisolated static func prefersPaste(bundleIdentifier: String?) -> Bool {
    switch bundleIdentifier {
    case "com.apple.Safari",
         "com.brave.Browser",
         "com.google.Chrome",
         "company.thebrowser.dia":
      return true
    default:
      return false
    }
  }

  private func isStillFocused(_ target: Target) -> Bool {
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

    return CFEqual(value, target.element)
  }

  private func pasteAndRestoreClipboard(_ text: String) async {
    let pasteboard = NSPasteboard.general
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

    postPasteShortcut()
    try? await Task.sleep(for: .milliseconds(150))

    guard pasteboard.changeCount == insertedChangeCount else { return }
    pasteboard.clearContents()
    if !savedItems.isEmpty {
      pasteboard.writeObjects(savedItems)
    }
  }

  private func copyToClipboard(_ text: String) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
  }

  private func postPasteShortcut() {
    guard let source = CGEventSource(stateID: .combinedSessionState),
       let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
       let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
      return
    }

    keyDown.flags = .maskCommand
    keyUp.flags = .maskCommand
    keyDown.post(tap: .cghidEventTap)
    keyUp.post(tap: .cghidEventTap)
  }

  private func remember(_ route: Route, for bundleIdentifier: String?) {
    guard let bundleIdentifier else { return }
    routesByBundleIdentifier[bundleIdentifier] = route
  }
}

private extension CGRect {
  var area: CGFloat {
    guard !isNull else { return 0 }
    return width * height
  }
}
