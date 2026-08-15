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
      waitForPasteRead: {}
    ))

    let target = service.captureFocusedTarget()
    #expect(target != nil)
    await service.insert("dictated text", into: target)
    #expect(checkedProcessIdentifier == application.processIdentifier)
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
