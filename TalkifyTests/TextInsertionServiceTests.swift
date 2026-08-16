import AppKit
import ApplicationServices
import os
import Testing
@testable import Talkify

@MainActor
struct TextInsertionServiceTests {
  private enum InsertionRaceResult: Sendable {
    case insertionCompleted
    case deadlineExpired
  }

  private struct InsertionObservations: Sendable {
    var readerStarted = false
    var postedPaste = false
    var textAvailableWhileTargetReads: String?
  }

  @Test func everyFocusedTargetUsesPasteInsertion() async {
    let pasteboard = makePasteboard()
    pasteboard.clearContents()
    pasteboard.setString("previous clipboard", forType: .string)
    var textAvailableWhileTargetReads: String?

    let service = TextInsertionService(dependencies: .init(
      pasteboard: pasteboard,
      readClipboardItems: makeClipboardReader(for: pasteboard),
      snapshotTimeout: .milliseconds(100),
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

  @Test func fastSnapshotRestoresEveryClipboardTypeInOrder() async {
    let pasteboard = makePasteboard()
    pasteboard.clearContents()
    let customType = NSPasteboard.PasteboardType(
      "com.tgomareli.TalkifyTests.custom-data"
    )
    let previousString = "previous clipboard"
    let previousStringData = Data(previousString.utf8)
    let previousCustomData = Data([0x00, 0x2A, 0x7F, 0xFF])
    let previousItem = NSPasteboardItem()
    previousItem.setData(previousStringData, forType: .string)
    previousItem.setData(previousCustomData, forType: customType)
    pasteboard.writeObjects([previousItem])
    var postedPaste = false
    var textAvailableWhileTargetReads: String?

    let service = TextInsertionService(dependencies: .init(
      pasteboard: pasteboard,
      readClipboardItems: makeClipboardReader(for: pasteboard),
      snapshotTimeout: .milliseconds(100),
      focusedElement: { nil },
      frontmostApplication: { nil },
      isProcessRunning: { _ in true },
      isTargetFocused: { _ in true },
      postPasteShortcut: {
        postedPaste = true
        return true
      },
      waitForPasteRead: {
        textAvailableWhileTargetReads = pasteboard.string(forType: .string)
      }
    ))
    await service.insert("dictated text", into: makeTarget())

    let restoredItem = pasteboard.pasteboardItems?.first
    #expect(postedPaste)
    #expect(textAvailableWhileTargetReads == "dictated text")
    #expect(pasteboard.pasteboardItems?.count == 1)
    #expect(restoredItem?.types == [.string, customType])
    #expect(restoredItem?.data(forType: .string) == previousStringData)
    #expect(restoredItem?.data(forType: customType) == previousCustomData)
    #expect(pasteboard.string(forType: .string) == previousString)
  }

  @Test func fastEmptySnapshotRestoresClipboardToEmpty() async {
    let pasteboard = makePasteboard()
    pasteboard.clearContents()
    var postedPaste = false
    var textAvailableWhileTargetReads: String?

    let service = TextInsertionService(dependencies: .init(
      pasteboard: pasteboard,
      readClipboardItems: makeClipboardReader(for: pasteboard),
      snapshotTimeout: .milliseconds(100),
      focusedElement: { nil },
      frontmostApplication: { nil },
      isProcessRunning: { _ in true },
      isTargetFocused: { _ in true },
      postPasteShortcut: {
        postedPaste = true
        return true
      },
      waitForPasteRead: {
        textAvailableWhileTargetReads = pasteboard.string(forType: .string)
      }
    ))
    await service.insert("dictated text", into: makeTarget())

    #expect(postedPaste)
    #expect(textAvailableWhileTargetReads == "dictated text")
    #expect((pasteboard.pasteboardItems ?? []).isEmpty)
    #expect(pasteboard.string(forType: .string) == nil)
  }

  @Test func clipboardChangeDuringPasteIsNeverOverwritten() async {
    let pasteboard = makePasteboard()
    pasteboard.clearContents()
    pasteboard.setString("previous clipboard", forType: .string)

    let service = TextInsertionService(dependencies: .init(
      pasteboard: pasteboard,
      readClipboardItems: makeClipboardReader(for: pasteboard),
      snapshotTimeout: .milliseconds(100),
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
      readClipboardItems: makeClipboardReader(for: pasteboard),
      snapshotTimeout: .milliseconds(100),
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
      readClipboardItems: makeClipboardReader(for: pasteboard),
      snapshotTimeout: .milliseconds(100),
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
      readClipboardItems: makeClipboardReader(for: pasteboard),
      snapshotTimeout: .milliseconds(100),
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
      readClipboardItems: makeClipboardReader(for: pasteboard),
      snapshotTimeout: .milliseconds(100),
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

  @Test nonisolated func blockedClipboardReadDoesNotFreezeInsertion() async {
    let pasteboard = NSPasteboard(
      name: NSPasteboard.Name(
        "TextInsertionServiceTests-\(UUID().uuidString)"
      )
    )
    pasteboard.clearContents()
    pasteboard.setString("previous clipboard", forType: .string)

    let allowReaderToFinish = DispatchSemaphore(value: 0)
    let readerReleaseState = OSAllocatedUnfairLock(initialState: false)
    let observations = OSAllocatedUnfairLock(
      initialState: InsertionObservations()
    )
    let releaseReader: @Sendable () -> Void = {
      let shouldSignal = readerReleaseState.withLock { wasReleased in
        if wasReleased {
          return false
        }
        wasReleased = true
        return true
      }
      if shouldSignal {
        allowReaderToFinish.signal()
      }
    }
    defer {
      releaseReader()
    }

    // This named pasteboard belongs only to this test. AppKit does not declare
    // NSPasteboard Sendable even though the production read runs off-main.
    nonisolated(unsafe) let observedPasteboard = pasteboard
    let insert: @MainActor @Sendable () async -> Void = {
      let service = TextInsertionService(dependencies: .init(
        pasteboard: observedPasteboard,
        readClipboardItems: {
          observations.withLock { $0.readerStarted = true }
          allowReaderToFinish.wait()
          return []
        },
        snapshotTimeout: .milliseconds(100),
        focusedElement: { nil },
        frontmostApplication: { nil },
        isProcessRunning: { _ in true },
        isTargetFocused: { _ in true },
        postPasteShortcut: {
          observations.withLock { $0.postedPaste = true }
          return true
        },
        waitForPasteRead: {
          let text = observedPasteboard.string(forType: .string)
          observations.withLock {
            $0.textAvailableWhileTargetReads = text
          }
        }
      ))
      let target = TextInsertionService.Target(
        element: AXUIElementCreateSystemWide(),
        processIdentifier: 42,
        isSecure: false,
        displayID: nil
      )
      await service.insert("dictated text", into: target)
    }

    let result = await withTaskGroup(of: InsertionRaceResult.self) { group in
      group.addTask {
        await insert()
        return .insertionCompleted
      }
      group.addTask {
        try? await Task.sleep(for: .seconds(2))
        return .deadlineExpired
      }

      let firstResult = await group.next() ?? .deadlineExpired
      if case .deadlineExpired = firstResult {
        releaseReader()
      }
      group.cancelAll()
      return firstResult
    }

    let finalObservations = observations.withLock { $0 }
    #expect(result == .insertionCompleted)
    #expect(finalObservations.readerStarted)
    #expect(finalObservations.postedPaste)
    #expect(
      finalObservations.textAvailableWhileTargetReads == "dictated text"
    )
    #expect(pasteboard.string(forType: .string) == "dictated text")
  }

  private func makePasteboard() -> NSPasteboard {
    NSPasteboard(
      name: NSPasteboard.Name("TextInsertionServiceTests-\(UUID().uuidString)")
    )
  }

  private nonisolated func makeClipboardReader(
    for pasteboard: NSPasteboard
  ) -> @Sendable () -> [TextInsertionService.ClipboardItemSnapshot] {
    // Named test pasteboards are isolated to one test, but AppKit does not
    // declare NSPasteboard Sendable for this background-capable API.
    nonisolated(unsafe) let backgroundPasteboard = pasteboard

    return {
      (backgroundPasteboard.pasteboardItems ?? []).map { sourceItem in
        let entries = sourceItem.types.compactMap { type in
          sourceItem.data(forType: type).map {
            TextInsertionService.ClipboardItemSnapshot.Entry(
              type: type,
              data: $0
            )
          }
        }
        return TextInsertionService.ClipboardItemSnapshot(entries: entries)
      }
    }
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
