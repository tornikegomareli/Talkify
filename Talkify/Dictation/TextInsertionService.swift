import AppKit
import ApplicationServices
import os

@MainActor
final class TextInsertionService {
  /// The terminal delivery state of one finalized Direct Dictation result.
  enum InsertionOutcome: Equatable, Sendable {
    /// The text was staged and pasted, or empty input completed as a no-op.
    case inserted
    /// Target delivery was unavailable, so the text was left for manual paste.
    case copiedToClipboard
    /// Neither target insertion nor a safe clipboard fallback was possible.
    case unavailable
  }

  /// Runs the sole leased pasteboard read away from the main actor.
  ///
  /// Apple documents no thread-safety contract for `NSPasteboard`. Background
  /// use is accepted only to keep promised-data resolution from blocking the
  /// main actor. The serial queue and read lease prevent same-instance overlap.
  let clipboardReaderQueue = DispatchQueue(
    label: "com.tgomareli.Talkify.clipboard-snapshot",
    qos: .userInitiated
  )

  /// True from before a read is enqueued until its closure actually returns.
  ///
  /// A timeout never clears this lease: while AppKit remains inside a promised
  /// data read, every later read and every write must remain excluded.
  let clipboardReadLease = OSAllocatedUnfairLock(initialState: false)

  struct Target {
    fileprivate let element: AXUIElement?
    fileprivate let processIdentifier: pid_t

    let isSecure: Bool
    let displayID: CGDirectDisplayID?
    /// The application that held focus when the session began, for the
    /// history entry to name. Resolved at capture time rather than at write
    /// time, because by then the application may be gone.
    let applicationName: String?

    init(
      element: AXUIElement?,
      processIdentifier: pid_t,
      isSecure: Bool,
      displayID: CGDirectDisplayID?,
      applicationName: String? = nil
    ) {
      self.element = element
      self.processIdentifier = processIdentifier
      self.isSecure = isSecure
      self.displayID = displayID
      self.applicationName = applicationName
    }
  }

  /// Injectable pasteboard, focus, event, and timing boundaries for insertion.
  struct Dependencies {
    let pasteboard: NSPasteboard
    /// Reads every pasteboard item into values that can cross back to the main actor.
    ///
    /// The service invokes this closure only on its serial reader queue while
    /// holding the read lease. `nil` means the read was incomplete or failed.
    let readClipboardItems: @Sendable () -> [ClipboardItemSnapshot]?
    /// The total acquisition deadline shared by the first read and one reread.
    let snapshotTimeout: Duration
    let focusedElement: @MainActor () -> AXUIElement?
    let frontmostApplication: @MainActor () -> NSRunningApplication?
    let isProcessRunning: @MainActor (pid_t) -> Bool
    let isTargetFocused: @MainActor (Target) -> Bool
    let postPasteShortcut: @MainActor () -> Bool
    let waitForPasteRead: @MainActor () async -> Void

    /// Builds the production boundaries around the shared general pasteboard.
    static var live: Self {
      let pasteboard = NSPasteboard.general
      // Apple documents no NSPasteboard thread-safety contract. This background
      // read is deliberate: promised data wedged the main actor in __dataForType
      // -> CFPasteboardCopyData -> mach_msg, while same-instance overlap was
      // proven to raise NSException "value not absent" in pasteboardItems. The
      // serial reader queue and lease exclude every write until the read returns.
      nonisolated(unsafe) let backgroundPasteboard = pasteboard

      return Self(
        pasteboard: pasteboard,
        readClipboardItems: {
          TextInsertionService.snapshot(of: backgroundPasteboard)
        },
        snapshotTimeout: .milliseconds(600),
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
        waitForPasteRead: {
          try? await Task.sleep(for: .milliseconds(500))
        }
      )
    }
  }

  let dependencies: Dependencies

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
        displayID: displayID(for: element),
        applicationName: NSRunningApplication(
          processIdentifier: processIdentifier
        )?.localizedName
      )
    }

    // Some apps expose no focused AX element even while an editor has focus.
    // Keep the application as the safest available focus boundary.
    guard let application = dependencies.frontmostApplication() else { return nil }
    return Target(
      element: nil,
      processIdentifier: application.processIdentifier,
      isSecure: false,
      displayID: nil,
      applicationName: application.localizedName
    )
  }

  /// Delivers finalized text to its captured target, the clipboard, or both.
  ///
  /// - Parameters:
  ///   - text: The finalized text to deliver.
  ///   - target: The focus boundary captured when Direct Dictation began.
  ///   - destination: Where the session's settings say the text goes.
  /// - Returns: The terminal delivery outcome used by the session controller.
  func insert(
    _ text: String,
    into target: Target?,
    destination: InsertionDestination = .insert
  ) async -> InsertionOutcome {
    guard !text.isEmpty else { return .inserted }
    guard destination != .clipboardOnly else {
      return copyToClipboard(text)
    }
    guard let target else {
      return copyToClipboard(text)
    }

    guard dependencies.isProcessRunning(target.processIdentifier) else {
      return copyToClipboard(text)
    }

    guard dependencies.isTargetFocused(target) else {
      return copyToClipboard(text)
    }
    if destination == .both {
      return await pasteLeavingClipboard(text, into: target)
    }
    return await pasteAndRestoreClipboard(text, into: target)
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

  /// Stages, pastes, and conditionally restores one finalized result.
  ///
  /// - Parameters:
  ///   - text: The finalized text to insert.
  ///   - target: The validated focus boundary that should receive the paste.
  /// - Returns: The terminal delivery outcome after all safe fallbacks.
  private func pasteAndRestoreClipboard(
    _ text: String,
    into target: Target
  ) async -> InsertionOutcome {
    let acquisition = await snapshotClipboardItems()
    let savedItems: [ClipboardItemSnapshot]
    let acceptedChangeCount: Int

    switch acquisition {
    case let .accepted(items, changeCount):
      savedItems = items
      acceptedChangeCount = changeCount
    case .failed:
      return copyToClipboard(text)
    case .timedOut, .unstable, .busy:
      return .unavailable
    }

    guard dependencies.isTargetFocused(target) else {
      return copyToClipboard(text)
    }
    guard let insertedChangeCount = stageClipboardText(
      text,
      ifUnchangedSince: acceptedChangeCount
    ) else { return .unavailable }

    guard dependencies.postPasteShortcut() else {
      restoreClipboard(savedItems, ifUnchangedSince: insertedChangeCount)
      return .unavailable
    }
    await dependencies.waitForPasteRead()
    restoreClipboard(savedItems, ifUnchangedSince: insertedChangeCount)
    return .inserted
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
}

private extension CGRect {
  var area: CGFloat {
    guard !isNull else { return 0 }
    return width * height
  }
}
