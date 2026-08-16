import AppKit
import ApplicationServices
import Testing
@testable import Talkify

@MainActor
struct TextInsertionServiceTests {
  @Test func everyFocusedTargetUsesPasteInsertion() async {
    let pasteboard = makePasteboard()
    pasteboard.clearContents()
    pasteboard.setString("previous clipboard", forType: .string)
    var textAvailableWhileTargetReads: String?

    let service = TextInsertionService(dependencies: .init(
      pasteboard: pasteboard,
      focusedElement: { nil },
      frontmostApplication: { nil },
      isProcessRunning: { _ in true },
      isTargetFocused: { _ in true },
      postPasteShortcut: { true },
      postTypingText: { _ in false },
      waitForPasteRead: {
        textAvailableWhileTargetReads = pasteboard.string(forType: .string)
      }
    ))
    await service.insert("dictated text", into: makeTarget())

    #expect(textAvailableWhileTargetReads == "dictated text")
    #expect(pasteboard.string(forType: .string) == "previous clipboard")
  }

  @Test func clipboardChangeDuringPasteIsNeverOverwritten() async {
    let pasteboard = makePasteboard()
    pasteboard.clearContents()
    pasteboard.setString("previous clipboard", forType: .string)

    let service = TextInsertionService(dependencies: .init(
      pasteboard: pasteboard,
      focusedElement: { nil },
      frontmostApplication: { nil },
      isProcessRunning: { _ in true },
      isTargetFocused: { _ in true },
      postPasteShortcut: { true },
      postTypingText: { _ in false },
      waitForPasteRead: {
        pasteboard.clearContents()
        pasteboard.setString("new clipboard", forType: .string)
      }
    ))
    await service.insert("dictated text", into: makeTarget())

    #expect(pasteboard.string(forType: .string) == "new clipboard")
  }

  @Test func failedPasteShortcutLeavesTranscriptOnClipboard() async {
    let pasteboard = makePasteboard()
    pasteboard.clearContents()
    pasteboard.setString("previous clipboard", forType: .string)
    var waitedForPasteRead = false

    let service = TextInsertionService(dependencies: .init(
      pasteboard: pasteboard,
      focusedElement: { nil },
      frontmostApplication: { nil },
      isProcessRunning: { _ in true },
      isTargetFocused: { _ in true },
      postPasteShortcut: { false },
      postTypingText: { _ in false },
      waitForPasteRead: {
        waitedForPasteRead = true
      }
    ))
    await service.insert("dictated text", into: makeTarget())

    #expect(pasteboard.string(forType: .string) == "dictated text")
    #expect(!waitedForPasteRead)
  }

  @Test func changedTargetReceivesNoPasteEvent() async {
    let pasteboard = makePasteboard()
    var postedPaste = false
    let service = TextInsertionService(dependencies: .init(
      pasteboard: pasteboard,
      focusedElement: { nil },
      frontmostApplication: { nil },
      isProcessRunning: { _ in true },
      isTargetFocused: { _ in false },
      postPasteShortcut: {
        postedPaste = true
        return true
      },
      postTypingText: { _ in false },
      waitForPasteRead: {}
    ))
    await service.insert("dictated text", into: makeTarget())

    #expect(!postedPaste)
    #expect(pasteboard.string(forType: .string) == "dictated text")
  }

  @Test func targetChangedWhileStagingReceivesNoPasteEvent() async {
    let pasteboard = makePasteboard()
    var focusCheckCount = 0
    var postedPaste = false
    let service = TextInsertionService(dependencies: .init(
      pasteboard: pasteboard,
      focusedElement: { nil },
      frontmostApplication: { nil },
      isProcessRunning: { _ in true },
      isTargetFocused: { _ in
        focusCheckCount += 1
        return focusCheckCount == 1
      },
      postPasteShortcut: {
        postedPaste = true
        return true
      },
      postTypingText: { _ in false },
      waitForPasteRead: {}
    ))
    await service.insert("dictated text", into: makeTarget())

    #expect(focusCheckCount == 2)
    #expect(!postedPaste)
    #expect(pasteboard.string(forType: .string) == "dictated text")
  }

  @Test func missingFocusedElementCapturesFrontmostApplication() async {
    let pasteboard = makePasteboard()
    let application = NSRunningApplication.current
    var checkedProcessIdentifier: pid_t?
    let service = TextInsertionService(dependencies: .init(
      pasteboard: pasteboard,
      focusedElement: { nil },
      frontmostApplication: { application },
      isProcessRunning: { processIdentifier in
        checkedProcessIdentifier = processIdentifier
        return false
      },
      isTargetFocused: { _ in true },
      postPasteShortcut: { true },
      postTypingText: { _ in false },
      waitForPasteRead: {}
    ))

    let target = service.captureFocusedTarget()
    #expect(target != nil)
    await service.insert("dictated text", into: target)
    #expect(checkedProcessIdentifier == application.processIdentifier)
  }

  @Test func typingMethodTypesWithoutTouchingClipboard() async {
    let pasteboard = makePasteboard()
    pasteboard.clearContents()
    pasteboard.setString("previous clipboard", forType: .string)
    var typedText: String?
    var postedPaste = false

    let service = TextInsertionService(dependencies: .init(
      pasteboard: pasteboard,
      focusedElement: { nil },
      frontmostApplication: { nil },
      isProcessRunning: { _ in true },
      isTargetFocused: { _ in true },
      postPasteShortcut: {
        postedPaste = true
        return true
      },
      postTypingText: { text in
        typedText = text
        return true
      },
      waitForPasteRead: {}
    ))
    await service.insert("dictated text", into: makeTarget(), method: .typing)

    #expect(typedText == "dictated text")
    #expect(!postedPaste)
    #expect(pasteboard.string(forType: .string) == "previous clipboard")
  }

  @Test func failedTypingLeavesTranscriptOnClipboard() async {
    let pasteboard = makePasteboard()
    pasteboard.clearContents()

    let service = TextInsertionService(dependencies: .init(
      pasteboard: pasteboard,
      focusedElement: { nil },
      frontmostApplication: { nil },
      isProcessRunning: { _ in true },
      isTargetFocused: { _ in true },
      postPasteShortcut: { true },
      postTypingText: { _ in false },
      waitForPasteRead: {}
    ))
    await service.insert("dictated text", into: makeTarget(), method: .typing)

    #expect(pasteboard.string(forType: .string) == "dictated text")
  }

  @Test func changedTargetReceivesNoTypingEvent() async {
    let pasteboard = makePasteboard()
    var postedTyping = false
    let service = TextInsertionService(dependencies: .init(
      pasteboard: pasteboard,
      focusedElement: { nil },
      frontmostApplication: { nil },
      isProcessRunning: { _ in true },
      isTargetFocused: { _ in false },
      postPasteShortcut: { true },
      postTypingText: { _ in
        postedTyping = true
        return true
      },
      waitForPasteRead: {}
    ))
    await service.insert("dictated text", into: makeTarget(), method: .typing)

    #expect(!postedTyping)
    #expect(pasteboard.string(forType: .string) == "dictated text")
  }

  private func makePasteboard() -> NSPasteboard {
    NSPasteboard(
      name: NSPasteboard.Name("TextInsertionServiceTests-\(UUID().uuidString)")
    )
  }

  private func makeTarget() -> TextInsertionService.Target {
    TextInsertionService.Target(
      element: AXUIElementCreateSystemWide(),
      processIdentifier: 42,
      isSecure: false,
      displayID: nil
    )
  }
}
