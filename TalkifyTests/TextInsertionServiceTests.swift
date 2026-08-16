import AppKit
import ApplicationServices
import os
import Testing
@testable import Talkify

@MainActor
struct TextInsertionServiceTests {
  /// Verifies every validated target uses paste insertion and restores text.
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
    let outcome = await service.insert("dictated text", into: makeTarget())

    #expect(outcome == .inserted)
    #expect(textAvailableWhileTargetReads == "dictated text")
    #expect(pasteboard.string(forType: .string) == "previous clipboard")
  }

  /// Verifies snapshot restoration preserves ordered multi-type item payloads.
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
    let outcome = await service.insert("dictated text", into: makeTarget())

    let restoredItem = pasteboard.pasteboardItems?.first
    #expect(outcome == .inserted)
    #expect(postedPaste)
    #expect(textAvailableWhileTargetReads == "dictated text")
    #expect(pasteboard.pasteboardItems?.count == 1)
    #expect(restoredItem?.types == [.string, customType])
    #expect(restoredItem?.data(forType: .string) == previousStringData)
    #expect(restoredItem?.data(forType: customType) == previousCustomData)
    #expect(pasteboard.string(forType: .string) == previousString)
  }

  /// Verifies a confirmed empty clipboard restores to empty after the paste.
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
    let outcome = await service.insert("dictated text", into: makeTarget())

    #expect(outcome == .inserted)
    #expect(postedPaste)
    #expect(textAvailableWhileTargetReads == "dictated text")
    #expect((pasteboard.pasteboardItems ?? []).isEmpty)
    #expect(pasteboard.string(forType: .string) == nil)
  }

  /// Verifies a completed nil read uses manual clipboard delivery without paste.
  @Test func failedClipboardReadUsesCopyFallbackWithoutPostingPaste() async {
    let pasteboard = makePasteboard()
    pasteboard.clearContents()
    pasteboard.setString("previous clipboard", forType: .string)
    var postedPaste = false
    var textAvailableWhileTargetReads: String?

    let service = TextInsertionService(dependencies: .init(
      pasteboard: pasteboard,
      readClipboardItems: { nil },
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
    let outcome = await service.insert("dictated text", into: makeTarget())

    #expect(outcome == .copiedToClipboard)
    #expect(!postedPaste)
    #expect(textAvailableWhileTargetReads == nil)
    #expect(pasteboard.string(forType: .string) == "dictated text")
  }

  /// Verifies a missing advertised payload rejects the partial snapshot.
  @Test func missingClipboardRepresentationUsesCopyFallback() async {
    let pasteboard = makePasteboard()
    let missingType = NSPasteboard.PasteboardType(
      "com.tgomareli.TalkifyTests.missing-data"
    )
    let provider = MissingPasteboardDataProvider()
    let item = NSPasteboardItem()
    item.setDataProvider(provider, forTypes: [missingType])
    pasteboard.clearContents()
    pasteboard.writeObjects([item])
    var postedPaste = false

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
      waitForPasteRead: {}
    ))

    let outcome = await service.insert("dictated text", into: makeTarget())

    #expect(outcome == .copiedToClipboard)
    #expect(!postedPaste)
    #expect(pasteboard.string(forType: .string) == "dictated text")
  }

  /// Verifies an external write after staging is not overwritten by restore.
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
    let outcome = await service.insert("dictated text", into: makeTarget())

    #expect(outcome == .inserted)
    #expect(pasteboard.string(forType: .string) == "new clipboard")
  }

  /// Verifies a healthy delayed read still pastes and restores within its budget.
  @Test func delayedSnapshotWithinDeadlinePastesAndRestores() async {
    let pasteboard = makePasteboard()
    pasteboard.clearContents()
    pasteboard.setString("previous clipboard", forType: .string)
    let delay = DispatchSemaphore(value: 0)
    var pastedText: String?

    nonisolated(unsafe) let backgroundPasteboard = pasteboard
    let service = TextInsertionService(dependencies: .init(
      pasteboard: pasteboard,
      readClipboardItems: {
        _ = delay.wait(timeout: .now() + .milliseconds(40))
        return TextInsertionService.snapshot(of: backgroundPasteboard)
      },
      snapshotTimeout: .milliseconds(150),
      focusedElement: { nil },
      frontmostApplication: { nil },
      isProcessRunning: { _ in true },
      isTargetFocused: { _ in true },
      postPasteShortcut: { true },
      waitForPasteRead: {
        pastedText = pasteboard.string(forType: .string)
      }
    ))

    let outcome = await service.insert("dictated text", into: makeTarget())

    #expect(outcome == .inserted)
    #expect(pastedText == "dictated text")
    #expect(pasteboard.string(forType: .string) == "previous clipboard")
  }

  /// Verifies one changed read accepts and restores the stable second snapshot.
  @Test func oneClipboardChangeUsesStableSecondSnapshot() async {
    let pasteboard = makePasteboard()
    pasteboard.clearContents()
    pasteboard.setString("first clipboard", forType: .string)
    let readCount = OSAllocatedUnfairLock(initialState: 0)
    var pastedText: String?

    nonisolated(unsafe) let backgroundPasteboard = pasteboard
    let service = TextInsertionService(dependencies: .init(
      pasteboard: pasteboard,
      readClipboardItems: {
        let attempt = readCount.withLock { count in
          count += 1
          return count
        }
        let snapshot = TextInsertionService.snapshot(of: backgroundPasteboard)
        if attempt == 1 {
          backgroundPasteboard.clearContents()
          backgroundPasteboard.setString("second clipboard", forType: .string)
        }
        return snapshot
      },
      snapshotTimeout: .milliseconds(100),
      focusedElement: { nil },
      frontmostApplication: { nil },
      isProcessRunning: { _ in true },
      isTargetFocused: { _ in true },
      postPasteShortcut: { true },
      waitForPasteRead: {
        pastedText = pasteboard.string(forType: .string)
      }
    ))

    let outcome = await service.insert("dictated text", into: makeTarget())

    #expect(outcome == .inserted)
    #expect(readCount.withLock { $0 } == 2)
    #expect(pastedText == "dictated text")
    #expect(pasteboard.string(forType: .string) == "second clipboard")
  }

  /// Verifies two unstable reads leave the latest clipboard value untouched.
  @Test func changesDuringBothSnapshotReadsLeaveLatestClipboardUntouched() async {
    let pasteboard = makePasteboard()
    pasteboard.clearContents()
    pasteboard.setString("first clipboard", forType: .string)
    let readCount = OSAllocatedUnfairLock(initialState: 0)
    var postedPaste = false

    nonisolated(unsafe) let backgroundPasteboard = pasteboard
    let service = TextInsertionService(dependencies: .init(
      pasteboard: pasteboard,
      readClipboardItems: {
        let attempt = readCount.withLock { count in
          count += 1
          return count
        }
        let snapshot = TextInsertionService.snapshot(of: backgroundPasteboard)
        backgroundPasteboard.clearContents()
        backgroundPasteboard.setString(
          attempt == 1 ? "second clipboard" : "third clipboard",
          forType: .string
        )
        return snapshot
      },
      snapshotTimeout: .milliseconds(100),
      focusedElement: { nil },
      frontmostApplication: { nil },
      isProcessRunning: { _ in true },
      isTargetFocused: { _ in true },
      postPasteShortcut: {
        postedPaste = true
        return true
      },
      waitForPasteRead: {}
    ))

    let outcome = await service.insert("dictated text", into: makeTarget())

    #expect(outcome == .unavailable)
    #expect(readCount.withLock { $0 } == 2)
    #expect(!postedPaste)
    #expect(pasteboard.string(forType: .string) == "third clipboard")
  }

  /// Verifies a count change after acquisition prevents any staging or paste.
  @Test func clipboardChangeAfterAcceptedSnapshotPreventsStaging() async {
    let pasteboard = makePasteboard()
    pasteboard.clearContents()
    pasteboard.setString("previous clipboard", forType: .string)
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
        if focusCheckCount == 2 {
          pasteboard.clearContents()
          pasteboard.setString("new clipboard", forType: .string)
        }
        return true
      },
      postPasteShortcut: {
        postedPaste = true
        return true
      },
      waitForPasteRead: {}
    ))

    let outcome = await service.insert("dictated text", into: makeTarget())

    #expect(outcome == .unavailable)
    #expect(focusCheckCount == 2)
    #expect(!postedPaste)
    #expect(pasteboard.string(forType: .string) == "new clipboard")
  }

  /// Verifies shortcut construction failure restores immediately and reports it.
  @Test func failedPasteShortcutRestoresClipboardAndReportsUnavailable() async {
    let pasteboard = makePasteboard()
    pasteboard.clearContents()
    pasteboard.setString("previous clipboard", forType: .string)
    var waitedForPasteRead = false
    var attemptedPaste = false
    var stagedTextAtPasteAttempt: String?

    let service = TextInsertionService(dependencies: .init(
      pasteboard: pasteboard,
      readClipboardItems: makeClipboardReader(for: pasteboard),
      snapshotTimeout: .milliseconds(100),
      focusedElement: { nil },
      frontmostApplication: { nil },
      isProcessRunning: { _ in true },
      isTargetFocused: { _ in true },
      postPasteShortcut: {
        attemptedPaste = true
        stagedTextAtPasteAttempt = pasteboard.string(forType: .string)
        return false
      },
      waitForPasteRead: {
        waitedForPasteRead = true
      }
    ))
    let outcome = await service.insert("dictated text", into: makeTarget())

    #expect(outcome == .unavailable)
    #expect(attemptedPaste)
    #expect(stagedTextAtPasteAttempt == "dictated text")
    #expect(pasteboard.string(forType: .string) == "previous clipboard")
    #expect(!waitedForPasteRead)
  }

  /// Verifies an invalid initial target uses manual clipboard delivery.
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
    let outcome = await service.insert("dictated text", into: makeTarget())

    #expect(outcome == .copiedToClipboard)
    #expect(!postedPaste)
    #expect(pasteboard.string(forType: .string) == "dictated text")
  }

  /// Verifies focus loss during acquisition uses manual clipboard delivery.
  @Test func targetChangedAfterSnapshotUsesCopyFallback() async {
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
    let outcome = await service.insert("dictated text", into: makeTarget())

    #expect(outcome == .copiedToClipboard)
    #expect(focusCheckCount == 2)
    #expect(!postedPaste)
    #expect(pasteboard.string(forType: .string) == "dictated text")
  }

  /// Verifies an exited frontmost target uses the existing clipboard fallback.
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
    let outcome = await service.insert("dictated text", into: target)
    #expect(checkedProcessIdentifier == application.processIdentifier)
    #expect(outcome == .copiedToClipboard)
  }

  /// Verifies a timed-out result stays unavailable after its reader releases the lease.
  @Test nonisolated func timeoutRemainsUnavailableAfterReaderReturnsBeforeRouting() async {
    let pasteboard = NSPasteboard(
      name: NSPasteboard.Name(
        "TextInsertionServiceTests-\(UUID().uuidString)"
      )
    )
    pasteboard.clearContents()
    pasteboard.setString("previous clipboard", forType: .string)

    let eventWaitBudget = DispatchTimeInterval.seconds(2)
    let blockingWaitBudget = DispatchTimeInterval.seconds(10)
    let snapshotTimeout = Duration.milliseconds(25)
    let readerStartedForBlocker = DispatchSemaphore(value: 0)
    let readerStartedForTest = DispatchSemaphore(value: 0)
    let allowReaderToFinish = DispatchSemaphore(value: 0)
    let mainActorBlocked = DispatchSemaphore(value: 0)
    let allowMainActorToResume = DispatchSemaphore(value: 0)
    let blockerFinished = DispatchSemaphore(value: 0)
    let blockerScheduled = OSAllocatedUnfairLock(initialState: false)
    let blockerObservedReaderStart = OSAllocatedUnfairLock(initialState: false)
    let blockerReleasedByTest = OSAllocatedUnfairLock(initialState: false)
    let readerReleasedByTest = OSAllocatedUnfairLock(initialState: false)
    let insertionCompleted = OSAllocatedUnfairLock(initialState: false)
    let postedPaste = OSAllocatedUnfairLock(initialState: false)
    defer {
      allowReaderToFinish.signal()
      allowMainActorToResume.signal()
    }

    nonisolated(unsafe) let observedPasteboard = pasteboard
    let service = await MainActor.run {
      TextInsertionService(dependencies: .init(
        pasteboard: observedPasteboard,
        readClipboardItems: {
          readerStartedForBlocker.signal()
          readerStartedForTest.signal()
          let releaseResult = allowReaderToFinish.wait(
            timeout: .now() + blockingWaitBudget
          )
          readerReleasedByTest.withLock {
            $0 = releaseResult == .success
          }
          guard releaseResult == .success else { return nil }
          return TextInsertionService.snapshot(of: observedPasteboard)
        },
        snapshotTimeout: snapshotTimeout,
        focusedElement: { nil },
        frontmostApplication: { nil },
        isProcessRunning: { _ in true },
        isTargetFocused: { _ in
          let shouldScheduleBlocker = blockerScheduled.withLock { scheduled in
            guard !scheduled else { return false }
            scheduled = true
            return true
          }
          if shouldScheduleBlocker {
            DispatchQueue.main.async {
              let readerStartResult = readerStartedForBlocker.wait(
                timeout: .now() + eventWaitBudget
              )
              blockerObservedReaderStart.withLock {
                $0 = readerStartResult == .success
              }
              mainActorBlocked.signal()

              if readerStartResult == .success {
                let releaseResult = allowMainActorToResume.wait(
                  timeout: .now() + blockingWaitBudget
                )
                blockerReleasedByTest.withLock {
                  $0 = releaseResult == .success
                }
              }
              blockerFinished.signal()
            }
          }
          return true
        },
        postPasteShortcut: {
          postedPaste.withLock { $0 = true }
          return true
        },
        waitForPasteRead: {}
      ))
    }
    let clipboardReaderQueue = await MainActor.run {
      service.clipboardReaderQueue
    }

    let insertion = Task { @MainActor in
      let outcome = await service.insert("dictated text", into: makeTarget())
      insertionCompleted.withLock { $0 = true }
      return outcome
    }
    #expect(
      wait(
        for: readerStartedForTest,
        timeout: .now() + eventWaitBudget
      ) == .success
    )
    #expect(
      wait(for: mainActorBlocked, timeout: .now() + eventWaitBudget) == .success
    )
    #expect(blockerObservedReaderStart.withLock { $0 })
    #expect(!insertionCompleted.withLock { $0 })

    let snapshotDeadlineElapsed = DispatchSemaphore(value: 0)
    DispatchQueue.global(qos: .userInitiated).asyncAfter(
      deadline: .now() + .milliseconds(30)
    ) {
      snapshotDeadlineElapsed.signal()
    }
    #expect(
      wait(
        for: snapshotDeadlineElapsed,
        timeout: .now() + eventWaitBudget
      ) == .success
    )

    allowReaderToFinish.signal()
    let readerQueueDrained = DispatchSemaphore(value: 0)
    clipboardReaderQueue.async(flags: .barrier) {
      readerQueueDrained.signal()
    }
    #expect(
      wait(for: readerQueueDrained, timeout: .now() + eventWaitBudget)
        == .success
    )
    #expect(readerReleasedByTest.withLock { $0 })
    #expect(!insertionCompleted.withLock { $0 })

    allowMainActorToResume.signal()
    #expect(
      wait(for: blockerFinished, timeout: .now() + eventWaitBudget) == .success
    )
    #expect(blockerReleasedByTest.withLock { $0 })

    let outcome = await insertion.value
    #expect(outcome == .unavailable)
    #expect(!postedPaste.withLock { $0 })
    #expect(pasteboard.string(forType: .string) == "previous clipboard")
  }

  /// Verifies a live read lease skips concurrent work and permits later recovery.
  @Test nonisolated func activeReadSkipsLaterInsertionImmediatelyAndRecovers() async {
    let pasteboard = NSPasteboard(
      name: NSPasteboard.Name(
        "TextInsertionServiceTests-\(UUID().uuidString)"
      )
    )
    pasteboard.clearContents()
    pasteboard.setString("previous clipboard", forType: .string)

    let readerStarted = DispatchSemaphore(value: 0)
    let allowFirstReadToFinish = DispatchSemaphore(value: 0)
    let readerReturned = DispatchSemaphore(value: 0)
    let readerReleaseState = OSAllocatedUnfairLock(initialState: false)
    let readCount = OSAllocatedUnfairLock(initialState: 0)
    let postedPasteCount = OSAllocatedUnfairLock(initialState: 0)
    let pastedTexts = OSAllocatedUnfairLock(initialState: [String]())
    let releaseReader: @Sendable () -> Void = {
      let shouldSignal = readerReleaseState.withLock { wasReleased in
        if wasReleased {
          return false
        }
        wasReleased = true
        return true
      }
      if shouldSignal {
        allowFirstReadToFinish.signal()
      }
    }
    defer {
      releaseReader()
    }

    nonisolated(unsafe) let observedPasteboard = pasteboard
    let service = await MainActor.run {
      TextInsertionService(dependencies: .init(
        pasteboard: observedPasteboard,
        readClipboardItems: {
          let attempt = readCount.withLock { count in
            count += 1
            return count
          }
          if attempt == 1 {
            readerStarted.signal()
            allowFirstReadToFinish.wait()
          }
          let snapshot = TextInsertionService.snapshot(of: observedPasteboard)
          if attempt == 1 {
            readerReturned.signal()
          }
          return snapshot
        },
        snapshotTimeout: .milliseconds(100),
        focusedElement: { nil },
        frontmostApplication: { nil },
        isProcessRunning: { _ in true },
        isTargetFocused: { _ in true },
        postPasteShortcut: {
          postedPasteCount.withLock { $0 += 1 }
          return true
        },
        waitForPasteRead: {
          if let text = observedPasteboard.string(forType: .string) {
            pastedTexts.withLock { $0.append(text) }
          }
        }
      ))
    }
    let insert: @MainActor @Sendable (String) async
      -> TextInsertionService.InsertionOutcome = { text in
      await service.insert(text, into: makeTarget())
    }

    let firstInsertion = Task {
      await insert("first dictated text")
    }
    #expect(wait(for: readerStarted, timeout: .now() + 1) == .success)

    let busySkipStarted = ContinuousClock.now
    let secondOutcome = await insert("second dictated text")
    let busySkipDuration = busySkipStarted.duration(to: .now)

    #expect(secondOutcome == .unavailable)
    // A generous ceiling on purpose. What proves the busy path did not queue
    // behind the stuck read is that it returned at all: the first read is held
    // open until `releaseReader()`, so an implementation that waited for it
    // would hang here rather than come back slowly. A tight bound measures the
    // runner's load instead, which failed this test on CI at 50ms.
    #expect(busySkipDuration < .seconds(2))
    #expect(readCount.withLock { $0 } == 1)
    #expect(postedPasteCount.withLock { $0 } == 0)
    #expect(pastedTexts.withLock { $0 }.isEmpty)
    #expect(pasteboard.string(forType: .string) == "previous clipboard")

    let firstOutcome = await firstInsertion.value
    #expect(firstOutcome == .unavailable)
    #expect(readCount.withLock { $0 } == 1)
    #expect(postedPasteCount.withLock { $0 } == 0)
    #expect(pasteboard.string(forType: .string) == "previous clipboard")

    releaseReader()
    #expect(wait(for: readerReturned, timeout: .now() + 1) == .success)
    // The reader signals from inside the read closure, so the lease is still
    // held for a moment after it. Retrying rather than sleeping a fixed 10ms
    // keeps this from depending on how fast the machine gets there; a refused
    // attempt reads nothing and posts nothing, so the counts below still only
    // count the recovery.
    var recoveryOutcome = TextInsertionService.InsertionOutcome.unavailable
    for _ in 0..<200 where recoveryOutcome == .unavailable {
      recoveryOutcome = await insert("third dictated text")
      if recoveryOutcome == .unavailable {
        try? await Task.sleep(for: .milliseconds(10))
      }
    }

    #expect(recoveryOutcome == .inserted)
    #expect(readCount.withLock { $0 } == 2)
    #expect(postedPasteCount.withLock { $0 } == 1)
    #expect(pastedTexts.withLock { $0 } == ["third dictated text"])
    #expect(pasteboard.string(forType: .string) == "previous clipboard")
  }

  private func makePasteboard() -> NSPasteboard {
    NSPasteboard(
      name: NSPasteboard.Name("TextInsertionServiceTests-\(UUID().uuidString)")
    )
  }

  /// Waits for a test-only semaphore without invoking its no-async API from
  /// the surrounding asynchronous test body.
  ///
  /// - Parameters:
  ///   - semaphore: The synchronization point to wait for.
  ///   - timeout: The absolute deadline that bounds the test wait.
  /// - Returns: Whether the semaphore was signaled before the deadline.
  private nonisolated func wait(
    for semaphore: DispatchSemaphore,
    timeout: DispatchTime
  ) -> DispatchTimeoutResult {
    semaphore.wait(timeout: timeout)
  }

  /// Builds the same optional all-or-nothing snapshot closure used in production.
  ///
  /// The closure retains the named pasteboard for background use so tests keep
  /// the production reader's isolation and lifetime semantics.
  ///
  /// - Parameter pasteboard: The test pasteboard captured by the reader.
  /// - Returns: A Sendable closure that distinguishes failure from empty state.
  private nonisolated func makeClipboardReader(
    for pasteboard: NSPasteboard
  ) -> @Sendable () -> [TextInsertionService.ClipboardItemSnapshot]? {
    // Named test pasteboards are isolated to one test, but AppKit does not
    // declare NSPasteboard Sendable for this background-capable API.
    nonisolated(unsafe) let backgroundPasteboard = pasteboard

    return {
      TextInsertionService.snapshot(of: backgroundPasteboard)
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

/// Advertises a type while withholding its data to model a partial AppKit read.
private final class MissingPasteboardDataProvider:
  NSObject,
  NSPasteboardItemDataProvider {
  /// Deliberately supplies no value for the requested representation.
  ///
  /// - Parameters:
  ///   - pasteboard: The pasteboard requesting its promised data.
  ///   - item: The item whose advertised representation is requested.
  ///   - type: The advertised type for which this provider withholds data.
  func pasteboard(
    _ pasteboard: NSPasteboard?,
    item: NSPasteboardItem,
    provideDataForType type: NSPasteboard.PasteboardType
  ) {}
}
