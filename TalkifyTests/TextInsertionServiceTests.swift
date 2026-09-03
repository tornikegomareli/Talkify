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
      },
      clock: makeHeldClock()
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
      },
      clock: makeHeldClock()
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
      },
      clock: makeHeldClock()
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
      },
      clock: makeHeldClock()
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
      waitForPasteRead: {},
      clock: makeHeldClock()
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
      },
      clock: makeHeldClock()
    ))
    let outcome = await service.insert("dictated text", into: makeTarget())

    #expect(outcome == .inserted)
    #expect(pasteboard.string(forType: .string) == "new clipboard")
  }

  /// Verifies a healthy delayed read still pastes and restores within its budget.
  ///
  /// The delay is in driven-clock time: the read is held open across a 100ms
  /// advance of a 150ms budget, so what is asserted is that a slow but
  /// in-budget read pastes, not that this machine got there in time.
  @Test nonisolated func delayedSnapshotWithinDeadlinePastesAndRestores() async {
    let pasteboard = NSPasteboard(
      name: NSPasteboard.Name(
        "TextInsertionServiceTests-\(UUID().uuidString)"
      )
    )
    pasteboard.clearContents()
    pasteboard.setString("previous clipboard", forType: .string)
    let clock = DrivenClock()
    let readerStarted = DispatchSemaphore(value: 0)
    let allowReadToFinish = DispatchSemaphore(value: 0)
    let pastedText = OSAllocatedUnfairLock<String?>(initialState: nil)
    defer {
      allowReadToFinish.signal()
    }

    nonisolated(unsafe) let observedPasteboard = pasteboard
    let service = await MainActor.run {
      TextInsertionService(dependencies: .init(
        pasteboard: observedPasteboard,
        readClipboardItems: {
          readerStarted.signal()
          _ = allowReadToFinish.wait(timeout: .now() + 10)
          return TextInsertionService.snapshot(of: observedPasteboard)
        },
        snapshotTimeout: .milliseconds(150),
        focusedElement: { nil },
        frontmostApplication: { nil },
        isProcessRunning: { _ in true },
        isTargetFocused: { _ in true },
        postPasteShortcut: { true },
        waitForPasteRead: {
          pastedText.withLock { $0 = observedPasteboard.string(forType: .string) }
        },
        clock: clock.insertionClock
      ))
    }

    let insertion = Task { @MainActor in
      await service.insert("dictated text", into: makeTarget())
    }
    #expect(wait(for: readerStarted, timeout: .now() + 10) == .success)
    clock.advance(by: .milliseconds(100))
    allowReadToFinish.signal()

    let outcome = await insertion.value
    #expect(outcome == .inserted)
    #expect(pastedText.withLock { $0 } == "dictated text")
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
      },
      clock: makeHeldClock()
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
      waitForPasteRead: {},
      clock: makeHeldClock()
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
      waitForPasteRead: {},
      clock: makeHeldClock()
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
      },
      clock: makeHeldClock()
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
      waitForPasteRead: {},
      clock: makeHeldClock()
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

    // An event wait, not a time bound: the budget is only spent when the run
    // is already broken, so it can be generous instead of measuring how fast
    // a loaded runner schedules the reader (#82).
    let eventWaitBudget = DispatchTimeInterval.seconds(10)
    let blockingWaitBudget = DispatchTimeInterval.seconds(10)
    let snapshotTimeout = Duration.milliseconds(25)
    let clock = DrivenClock()
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
        waitForPasteRead: {},
        clock: clock.insertionClock
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

    // Drive the injected clock past the snapshot budget instead of sleeping
    // it away: the timeout is forced by the test, not raced against the
    // runner (#82).
    await waitForSleeper(on: clock)
    clock.advance(by: snapshotTimeout)

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

    let clock = DrivenClock()
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
        },
        clock: clock.insertionClock
      ))
    }
    let insert: @MainActor @Sendable (String) async
      -> TextInsertionService.InsertionOutcome = { text in
      await service.insert(text, into: makeTarget())
    }

    let firstInsertion = Task {
      await insert("first dictated text")
    }
    // An event wait, not a time bound: the budget is only spent when the run
    // is already broken, so it can be generous instead of measuring how fast
    // a loaded runner schedules the reader (#82).
    #expect(wait(for: readerStarted, timeout: .now() + 10) == .success)

    let secondOutcome = await insert("second dictated text")

    #expect(secondOutcome == .unavailable)
    // The busy skip never consults the clock, and only this test advances it,
    // so coming back at all proves the skip did not queue behind the held-open
    // read: an implementation that waited for it would hang here forever. The
    // wall-clock ceiling this replaces measured the runner's load instead,
    // which failed this test on CI at 50ms.
    #expect(readCount.withLock { $0 } == 1)
    #expect(postedPasteCount.withLock { $0 } == 0)
    #expect(pastedTexts.withLock { $0 }.isEmpty)
    #expect(pasteboard.string(forType: .string) == "previous clipboard")

    // The held-open read is meant to outlive its budget: arm the deadline and
    // drive the clock past it, so the first insertion's timeout is forced
    // rather than waited for.
    await waitForSleeper(on: clock)
    clock.advance(by: .milliseconds(100))
    let firstOutcome = await firstInsertion.value
    #expect(firstOutcome == .unavailable)
    #expect(readCount.withLock { $0 } == 1)
    #expect(postedPasteCount.withLock { $0 } == 0)
    #expect(pasteboard.string(forType: .string) == "previous clipboard")

    releaseReader()
    #expect(wait(for: readerReturned, timeout: .now() + 10) == .success)
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

  /// The deadline is honoured, not raced: with the read held open, driving
  /// the clock past the snapshot budget is the only thing that times the
  /// acquisition out. No real time passes here, so a starved runner cannot
  /// change the answer either way.
  @Test nonisolated func drivingTheClockPastTheSnapshotBudgetTimesTheReadOut() async {
    let pasteboard = NSPasteboard(
      name: NSPasteboard.Name(
        "TextInsertionServiceTests-\(UUID().uuidString)"
      )
    )
    pasteboard.clearContents()
    pasteboard.setString("previous clipboard", forType: .string)
    let clock = DrivenClock()
    let readerStarted = DispatchSemaphore(value: 0)
    let allowReadToFinish = DispatchSemaphore(value: 0)
    let postedPaste = OSAllocatedUnfairLock(initialState: false)
    defer {
      allowReadToFinish.signal()
    }

    nonisolated(unsafe) let observedPasteboard = pasteboard
    let service = await MainActor.run {
      TextInsertionService(dependencies: .init(
        pasteboard: observedPasteboard,
        readClipboardItems: {
          readerStarted.signal()
          _ = allowReadToFinish.wait(timeout: .now() + 10)
          return TextInsertionService.snapshot(of: observedPasteboard)
        },
        snapshotTimeout: .milliseconds(100),
        focusedElement: { nil },
        frontmostApplication: { nil },
        isProcessRunning: { _ in true },
        isTargetFocused: { _ in true },
        postPasteShortcut: {
          postedPaste.withLock { $0 = true }
          return true
        },
        waitForPasteRead: {},
        clock: clock.insertionClock
      ))
    }

    let insertion = Task { @MainActor in
      await service.insert("dictated text", into: makeTarget())
    }
    #expect(wait(for: readerStarted, timeout: .now() + 10) == .success)
    await waitForSleeper(on: clock)
    clock.advance(by: .milliseconds(100))

    let outcome = await insertion.value
    #expect(outcome == .unavailable)
    #expect(!postedPaste.withLock { $0 })
    #expect(pasteboard.string(forType: .string) == "previous clipboard")
  }

  /// Verifies clipboard-only delivery replaces the clipboard without pasting.
  @Test func clipboardOnlyReplacesClipboardWithoutPosting() async {
    let pasteboard = makePasteboard()
    pasteboard.clearContents()
    pasteboard.setString("previous clipboard", forType: .string)
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
    let outcome = await service.insert(
      "dictated text",
      into: makeTarget(),
      destination: .clipboardOnly
    )

    #expect(outcome == .copiedToClipboard)
    #expect(!postedPaste)
    #expect(pasteboard.string(forType: .string) == "dictated text")
  }

  /// Verifies clipboard-only delivery never consults the target guards.
  @Test func clipboardOnlySkipsEveryTargetGuard() async {
    let pasteboard = makePasteboard()
    pasteboard.clearContents()

    let service = TextInsertionService(dependencies: .init(
      pasteboard: pasteboard,
      readClipboardItems: makeClipboardReader(for: pasteboard),
      snapshotTimeout: .milliseconds(100),
      focusedElement: { nil },
      frontmostApplication: { nil },
      isProcessRunning: { _ in false },
      isTargetFocused: { _ in false },
      postPasteShortcut: { true },
      waitForPasteRead: {}
    ))
    let outcome = await service.insert(
      "dictated text",
      into: makeTarget(),
      destination: .clipboardOnly
    )

    #expect(outcome == .copiedToClipboard)
    #expect(pasteboard.string(forType: .string) == "dictated text")
  }

  /// Verifies clipboard-only delivery succeeds without any captured target.
  @Test func clipboardOnlyDeliversWithoutTarget() async {
    let pasteboard = makePasteboard()
    pasteboard.clearContents()

    let service = TextInsertionService(dependencies: .init(
      pasteboard: pasteboard,
      readClipboardItems: makeClipboardReader(for: pasteboard),
      snapshotTimeout: .milliseconds(100),
      focusedElement: { nil },
      frontmostApplication: { nil },
      isProcessRunning: { _ in true },
      isTargetFocused: { _ in true },
      postPasteShortcut: { true },
      waitForPasteRead: {}
    ))
    let outcome = await service.insert(
      "dictated text",
      into: nil,
      destination: .clipboardOnly
    )

    #expect(outcome == .copiedToClipboard)
    #expect(pasteboard.string(forType: .string) == "dictated text")
  }

  /// Verifies insert-and-copy pastes once and leaves the text on the clipboard.
  @Test func bothPastesAndLeavesTextOnClipboard() async {
    let pasteboard = makePasteboard()
    pasteboard.clearContents()
    pasteboard.setString("previous clipboard", forType: .string)
    var postedPasteCount = 0
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
        postedPasteCount += 1
        return true
      },
      waitForPasteRead: {
        textAvailableWhileTargetReads = pasteboard.string(forType: .string)
      }
    ))
    let outcome = await service.insert(
      "dictated text",
      into: makeTarget(),
      destination: .both
    )

    #expect(outcome == .inserted)
    #expect(postedPasteCount == 1)
    #expect(textAvailableWhileTargetReads == "dictated text")
    #expect(pasteboard.string(forType: .string) == "dictated text")
  }

  /// Verifies insert-and-copy falls back to manual delivery on lost focus.
  @Test func bothWithUnfocusedTargetUsesCopyFallback() async {
    let pasteboard = makePasteboard()
    pasteboard.clearContents()
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
    let outcome = await service.insert(
      "dictated text",
      into: makeTarget(),
      destination: .both
    )

    #expect(outcome == .copiedToClipboard)
    #expect(!postedPaste)
    #expect(pasteboard.string(forType: .string) == "dictated text")
  }

  /// Verifies a failed paste shortcut leaves staged text as manual delivery.
  @Test func bothWithFailedPasteShortcutKeepsStagedText() async {
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
    let outcome = await service.insert(
      "dictated text",
      into: makeTarget(),
      destination: .both
    )

    #expect(outcome == .copiedToClipboard)
    #expect(!waitedForPasteRead)
    #expect(pasteboard.string(forType: .string) == "dictated text")
  }

  /// Verifies insert-and-copy refuses to stage while a read owns the lease.
  @Test func bothWithHeldReadLeaseReportsUnavailable() async {
    let pasteboard = makePasteboard()
    pasteboard.clearContents()
    pasteboard.setString("previous clipboard", forType: .string)
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
    service.clipboardReadLease.withLock { $0 = true }
    let outcome = await service.insert(
      "dictated text",
      into: makeTarget(),
      destination: .both
    )
    service.clipboardReadLease.withLock { $0 = false }

    #expect(outcome == .unavailable)
    #expect(!postedPaste)
    #expect(pasteboard.string(forType: .string) == "previous clipboard")
  }

  /// Verifies an explicit insert destination matches the default behavior.
  @Test func explicitInsertDestinationPastesThenRestores() async {
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
      },
      clock: makeHeldClock()
    ))
    let outcome = await service.insert(
      "dictated text",
      into: makeTarget(),
      destination: .insert
    )

    #expect(outcome == .inserted)
    #expect(textAvailableWhileTargetReads == "dictated text")
    #expect(pasteboard.string(forType: .string) == "previous clipboard")
  }

  /// Verifies empty text completes as a no-op before destination handling.
  @Test func emptyTextWithClipboardOnlyLeavesClipboardUntouched() async {
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
      waitForPasteRead: {}
    ))
    let outcome = await service.insert(
      "",
      into: makeTarget(),
      destination: .clipboardOnly
    )

    #expect(outcome == .inserted)
    #expect(pasteboard.string(forType: .string) == "previous clipboard")
  }

  /// The paste-and-restore write is marked as machine-generated and
  /// short-lived, so a clipboard manager honouring nspasteboard.com's types
  /// keeps every dictated phrase out of its history.
  @Test func theStagedPasteIsMarkedTransient() async {
    let pasteboard = makePasteboard()
    pasteboard.clearContents()
    pasteboard.setString("previous clipboard", forType: .string)
    var typesWhileStaged: [String] = []

    let service = TextInsertionService(dependencies: .init(
      pasteboard: pasteboard,
      readClipboardItems: makeClipboardReader(for: pasteboard),
      snapshotTimeout: .milliseconds(200),
      focusedElement: { nil },
      frontmostApplication: { nil },
      isProcessRunning: { _ in true },
      isTargetFocused: { _ in true },
      postPasteShortcut: {
        // Read while Talkify's text is on the pasteboard, which is the only
        // moment a clipboard manager would see it.
        typesWhileStaged = pasteboard.types?.map(\.rawValue) ?? []
        return true
      },
      waitForPasteRead: {},
      clock: makeHeldClock()
    ))

    let outcome = await service.insert(
      "dictated words",
      into: makeTarget(),
      destination: .insert
    )

    #expect(outcome == .inserted)
    #expect(typesWhileStaged.contains("org.nspasteboard.TransientType"))
    #expect(typesWhileStaged.contains("org.nspasteboard.AutoGeneratedType"))
    #expect(pasteboard.string(forType: .string) == "previous clipboard")
  }

  /// Insert and copy means keep it, so what stays behind is an ordinary copy
  /// and a clipboard manager should record it like any other.
  @Test func textMeantToStayIsNotMarkedTransient() async {
    let pasteboard = makePasteboard()
    pasteboard.clearContents()

    let service = TextInsertionService(dependencies: .init(
      pasteboard: pasteboard,
      readClipboardItems: makeClipboardReader(for: pasteboard),
      snapshotTimeout: .milliseconds(200),
      focusedElement: { nil },
      frontmostApplication: { nil },
      isProcessRunning: { _ in true },
      isTargetFocused: { _ in true },
      postPasteShortcut: { true },
      waitForPasteRead: {}
    ))

    let outcome = await service.insert(
      "dictated words",
      into: makeTarget(),
      destination: .both
    )

    #expect(outcome == .inserted)
    let types = pasteboard.types?.map(\.rawValue) ?? []
    #expect(!types.contains("org.nspasteboard.TransientType"))
    #expect(pasteboard.string(forType: .string) == "dictated words")
  }

  /// Copying is how a selection is read where Accessibility answers nothing,
  /// which is every browser. The clipboard has to come back afterwards.
  @Test func copyingASelectionReadsItAndPutsTheClipboardBack() async {
    let pasteboard = makePasteboard()
    pasteboard.clearContents()
    pasteboard.setString("previous clipboard", forType: .string)

    let service = TextInsertionService(dependencies: .init(
      pasteboard: pasteboard,
      readClipboardItems: makeClipboardReader(for: pasteboard),
      snapshotTimeout: .milliseconds(200),
      focusedElement: { nil },
      frontmostApplication: { nil },
      isProcessRunning: { _ in true },
      isTargetFocused: { _ in true },
      postPasteShortcut: { true },
      waitForPasteRead: {},
      // What Copy does in the focused application, which here is the selection
      // arriving on the pasteboard.
      postCopyShortcut: {
        pasteboard.clearContents()
        pasteboard.setString("the selected sentence", forType: .string)
        return true
      },
      clock: makeHeldClock()
    ))

    let copied = await service.copySelection()

    #expect(copied == "the selected sentence")
    #expect(pasteboard.string(forType: .string) == "previous clipboard")
  }

  /// Nothing selected is known, not guessed: Copy that finds nothing leaves
  /// the change count alone, so the old clipboard is never read back as if it
  /// were the selection.
  @Test func copyingWithNothingSelectedReadsNothing() async {
    let pasteboard = makePasteboard()
    pasteboard.clearContents()
    pasteboard.setString("previous clipboard", forType: .string)
    let clock = DrivenClock()
    let copyFired = OSAllocatedUnfairLock(initialState: false)

    let service = TextInsertionService(dependencies: .init(
      pasteboard: pasteboard,
      readClipboardItems: makeClipboardReader(for: pasteboard),
      snapshotTimeout: .milliseconds(200),
      focusedElement: { nil },
      frontmostApplication: { nil },
      isProcessRunning: { _ in true },
      isTargetFocused: { _ in true },
      postPasteShortcut: { true },
      waitForPasteRead: {},
      // Copy fired and nothing came of it, exactly as an empty selection does.
      postCopyShortcut: {
        copyFired.withLock { $0 = true }
        return true
      },
      copyTimeout: .milliseconds(60),
      clock: clock.insertionClock
    ))

    // The copy deadline is driven, not waited out. Advancing only once Copy
    // has fired keeps the snapshot's own timer out of it: by then that timer
    // is cancelled, so the sleeper this wakes is the copy poll's.
    let driver = Task.detached {
      while !copyFired.withLock({ $0 }) {
        await Task.yield()
      }
      while !clock.hasSleeper {
        await Task.yield()
      }
      clock.advance(by: .milliseconds(60))
    }
    let copied = await service.copySelection()
    await driver.value

    #expect(copied == nil)
    #expect(pasteboard.string(forType: .string) == "previous clipboard")
  }

  /// A clipboard that cannot be captured cannot be put back, so the copy is
  /// never attempted.
  @Test func copyingIsRefusedWhenTheClipboardCannotBeSnapshotted() async {
    let pasteboard = makePasteboard()
    pasteboard.clearContents()
    pasteboard.setString("previous clipboard", forType: .string)
    let didCopy = OSAllocatedUnfairLock(initialState: false)

    let service = TextInsertionService(dependencies: .init(
      pasteboard: pasteboard,
      readClipboardItems: { nil },
      snapshotTimeout: .milliseconds(200),
      focusedElement: { nil },
      frontmostApplication: { nil },
      isProcessRunning: { _ in true },
      isTargetFocused: { _ in true },
      postPasteShortcut: { true },
      waitForPasteRead: {},
      postCopyShortcut: {
        didCopy.withLock { $0 = true }
        return true
      },
      clock: makeHeldClock()
    ))

    let copied = await service.copySelection()

    #expect(copied == nil)
    #expect(didCopy.withLock { $0 } == false)
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

  /// A clock nothing advances. Deadlines armed on it can never elapse, so a
  /// test that expects no timeout cannot lose one to a starved runner, which
  /// is exactly how this family flaked on CI (#82).
  private nonisolated func makeHeldClock() -> InsertionClock {
    DrivenClock().insertionClock
  }

  /// Yields until the driven clock has a sleeper armed, so an advance lands
  /// on the deadline timer rather than into empty air before it starts
  /// waiting. An event wait, not a time bound: it costs nothing on a healthy
  /// run and hangs visibly on a broken one.
  private nonisolated func waitForSleeper(on clock: DrivenClock) async {
    while !clock.hasSleeper {
      await Task.yield()
    }
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

/// A clock the tests advance by hand, following the precedent #82 named: a
/// timeout test drives time rather than waiting for it, so the assertion is
/// that the deadline was honoured, not that the machine was fast enough.
private final class DrivenClock: Sendable {
  private struct Sleeper {
    let id: UUID
    let wakeAt: Duration
    let continuation: CheckedContinuation<Void, any Error>
  }

  private struct State {
    var now: Duration = .zero
    var sleepers: [Sleeper] = []
  }

  private let state = OSAllocatedUnfairLock(initialState: State())

  /// Whether any sleep is currently suspended on this clock.
  var hasSleeper: Bool {
    state.withLock { !$0.sleepers.isEmpty }
  }

  /// Moves the clock forward and wakes every sleep the move satisfies.
  func advance(by duration: Duration) {
    let woken = state.withLock { state -> [Sleeper] in
      state.now += duration
      let now = state.now
      let due = state.sleepers.filter { $0.wakeAt <= now }
      state.sleepers.removeAll { $0.wakeAt <= now }
      return due
    }
    for sleeper in woken {
      sleeper.continuation.resume()
    }
  }

  /// The injectable boundary handed to the service under test.
  var insertionClock: InsertionClock {
    InsertionClock(
      now: { [self] in state.withLock { $0.now } },
      sleep: { [self] in try await sleep(for: $0) }
    )
  }

  private func sleep(for duration: Duration) async throws {
    let id = UUID()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
        // The cancellation check shares the lock with the handler below, so
        // a cancel can never slip between checking and registering and leave
        // the sleep suspended forever.
        let cancelledBeforeRegistering = state.withLock { state -> Bool in
          guard !Task.isCancelled else { return true }
          state.sleepers.append(Sleeper(
            id: id,
            wakeAt: state.now + duration,
            continuation: continuation
          ))
          return false
        }
        if cancelledBeforeRegistering {
          continuation.resume(throwing: CancellationError())
        }
      }
    } onCancel: {
      let cancelled = state.withLock { state -> Sleeper? in
        guard let index = state.sleepers.firstIndex(where: { $0.id == id }) else {
          return nil
        }
        return state.sleepers.remove(at: index)
      }
      cancelled?.continuation.resume(throwing: CancellationError())
    }
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
