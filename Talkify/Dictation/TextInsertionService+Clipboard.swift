import AppKit
import os

/// Provides safe pasteboard access through its lease, budget, snapshots, staging, and restore.
extension TextInsertionService {
  /// The result of acquiring one stable, complete pre-insertion snapshot.
  enum SnapshotAcquisitionResult: Sendable {
    /// A complete snapshot whose count stayed stable during its read.
    case accepted(items: [ClipboardItemSnapshot], changeCount: Int)
    /// The actual read completed but could not capture every advertised value.
    case failed
    /// Both the initial read and the single permitted reread changed mid-read.
    case unstable
    /// The total acquisition deadline elapsed before a stable read completed.
    case timedOut
    /// Another acquisition still owns the service-wide read lease.
    case busy
  }

  /// A Sendable value copy of one pasteboard item's ordered type payloads.
  struct ClipboardItemSnapshot: Sendable {
    /// One pasteboard type and its byte-for-byte payload.
    struct Entry: Sendable {
      /// The pasteboard representation type advertised by the source item.
      let type: NSPasteboard.PasteboardType
      /// The complete payload returned for the advertised representation.
      let data: Data
    }

    /// Every advertised representation in the source item's original order.
    let entries: [Entry]
  }

  /// Copies every advertised pasteboard representation into Sendable values.
  ///
  /// Capture is all-or-nothing because restoring an item without one of its
  /// advertised representations would silently corrupt the clipboard.
  /// Callers must run this off the main actor on the serial reader queue while
  /// the read lease excludes same-instance writes: resolving promised values is
  /// the operation that can block indefinitely inside an unresponsive owner.
  ///
  /// - Parameter pasteboard: The pasteboard whose current items are copied.
  /// - Returns: Ordered item snapshots, including `[]` for a confirmed empty
  ///   pasteboard, or `nil` when AppKit cannot return every advertised value.
  static nonisolated func snapshot(
    of pasteboard: NSPasteboard
  ) -> [ClipboardItemSnapshot]? {
    guard let sourceItems = pasteboard.pasteboardItems else { return nil }

    var snapshots: [ClipboardItemSnapshot] = []
    snapshots.reserveCapacity(sourceItems.count)
    for sourceItem in sourceItems {
      var entries: [ClipboardItemSnapshot.Entry] = []
      entries.reserveCapacity(sourceItem.types.count)
      for type in sourceItem.types {
        guard let data = sourceItem.data(forType: type) else {
          // An incomplete restore would silently discard an advertised
          // representation, so abandon the whole snapshot instead.
          return nil
        }
        entries.append(ClipboardItemSnapshot.Entry(type: type, data: data))
      }
      snapshots.append(ClipboardItemSnapshot(entries: entries))
    }
    return snapshots
  }

  /// Acquires one stable snapshot under the service-wide read lease.
  ///
  /// The lease is claimed before queueing, so a busy acquisition returns
  /// without allocating a continuation or timer. A timeout resumes the caller
  /// but leaves the lease claimed until the actual AppKit read returns.
  ///
  /// - Returns: The accepted snapshot and count, or the exact reason that a
  ///   safe snapshot was unavailable.
  func snapshotClipboardItems() async -> SnapshotAcquisitionResult {
    let didClaimLease = clipboardReadLease.withLock { isClaimed in
      guard !isClaimed else { return false }
      isClaimed = true
      return true
    }
    guard didClaimLease else { return .busy }

    let readClipboardItems = dependencies.readClipboardItems
    let timeout = dependencies.snapshotTimeout
    let deadline = ContinuousClock.now.advanced(by: timeout)
    let completionLock = OSAllocatedUnfairLock(initialState: false)
    let readLease = clipboardReadLease
    let pasteboard = dependencies.pasteboard
    nonisolated(unsafe) let backgroundPasteboard = pasteboard

    return await withCheckedContinuation { continuation in
      let complete: @Sendable (SnapshotAcquisitionResult) -> Void = { result in
        // The reader and deadline can finish together; only the winner owns
        // the continuation, while the reader always owns lease release.
        let shouldResume = completionLock.withLock { didComplete in
          guard !didComplete else { return false }
          didComplete = true
          return true
        }
        if shouldResume {
          continuation.resume(returning: result)
        }
      }

      let timeoutTask = Self.makeSnapshotTimeoutTask(after: timeout) {
        complete(.timedOut)
      }
      let executeRead: @Sendable () -> Void = {
        let result = Self.readStableSnapshot(
          of: backgroundPasteboard,
          using: readClipboardItems,
          before: deadline
        )
        readLease.withLock { $0 = false }
        timeoutTask.cancel()
        complete(result)
      }
      clipboardReaderQueue.async(execute: executeRead)
    }
  }

  /// Reads at most twice and accepts only a complete, count-stable snapshot.
  ///
  /// This method runs on the serial reader queue while the read lease excludes
  /// every same-instance pasteboard write until the actual read returns.
  ///
  /// - Parameters:
  ///   - pasteboard: The pasteboard whose change count bounds each read.
  ///   - readClipboardItems: The all-or-nothing snapshot operation.
  ///   - deadline: The total deadline shared by both permitted reads.
  /// - Returns: A stable snapshot, a completed failure, an unstable result, or
  ///   a timeout when the second read cannot start or finish within the budget.
  private nonisolated static func readStableSnapshot(
    of pasteboard: NSPasteboard,
    using readClipboardItems: @Sendable () -> [ClipboardItemSnapshot]?,
    before deadline: ContinuousClock.Instant
  ) -> SnapshotAcquisitionResult {
    let startCount = pasteboard.changeCount
    let firstSnapshot = readClipboardItems()
    let firstEndCount = pasteboard.changeCount
    guard ContinuousClock.now < deadline else { return .timedOut }

    if firstEndCount == startCount {
      guard let firstSnapshot else { return .failed }
      return .accepted(items: firstSnapshot, changeCount: firstEndCount)
    }

    guard ContinuousClock.now < deadline else { return .timedOut }
    let secondStartCount = pasteboard.changeCount
    let secondSnapshot = readClipboardItems()
    let secondEndCount = pasteboard.changeCount
    guard ContinuousClock.now < deadline else { return .timedOut }
    guard secondEndCount == secondStartCount else { return .unstable }
    guard let secondSnapshot else { return .failed }
    return .accepted(items: secondSnapshot, changeCount: secondEndCount)
  }

  /// Starts the independent acquisition deadline without detaching execution.
  ///
  /// Cancelling the returned task stops the timer without invoking its handler.
  /// Caller cancellation does not shorten the clipboard acquisition budget.
  ///
  /// - Parameters:
  ///   - timeout: The total duration allowed for snapshot acquisition.
  ///   - onTimeout: The single-resume contender invoked when the budget elapses.
  /// - Returns: A task the actual reader must cancel when it completes.
  private nonisolated static func makeSnapshotTimeoutTask(
    after timeout: Duration,
    onTimeout: @escaping @Sendable () -> Void
  ) -> Task<Void, Never> {
    Task {
      do {
        try await Task.sleep(for: timeout)
      } catch {
        return
      }
      guard !Task.isCancelled else { return }
      onTimeout()
    }
  }

  /// Stages finalized text only while the accepted snapshot remains current.
  ///
  /// - Parameters:
  ///   - text: The finalized text to stage for paste.
  ///   - acceptedChangeCount: The stable count captured with the snapshot.
  /// - Returns: Talkify's staged change count, or `nil` when staging is unsafe.
  func stageClipboardText(
    _ text: String,
    ifUnchangedSince acceptedChangeCount: Int
  ) -> Int? {
    guard !isClipboardReadActive() else { return nil }

    let pasteboard = dependencies.pasteboard
    guard pasteboard.changeCount == acceptedChangeCount else { return nil }
    // Public pasteboard APIs cannot make this comparison and clear atomic. An
    // external write in the remaining instruction-level gap is knowingly lost;
    // insertion never waits on or aborts for it because delivery takes priority.
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
    return pasteboard.changeCount
  }

  /// Restores a saved snapshot only while Talkify still owns the staged value.
  ///
  /// - Parameters:
  ///   - savedItems: The complete item snapshots accepted before insertion.
  ///   - insertedChangeCount: The count produced by Talkify's staged text.
  func restoreClipboard(
    _ savedItems: [ClipboardItemSnapshot],
    ifUnchangedSince insertedChangeCount: Int
  ) {
    guard !isClipboardReadActive() else { return }

    let pasteboard = dependencies.pasteboard
    // This guard preserves clipboard contents written after Talkify staged the
    // dictated text.
    guard pasteboard.changeCount == insertedChangeCount else { return }

    pasteboard.clearContents()
    if !savedItems.isEmpty {
      let pasteboardItems = savedItems.map { snapshot in
        let item = NSPasteboardItem()
        for entry in snapshot.entries {
          item.setData(entry.data, forType: entry.type)
        }
        return item
      }
      pasteboard.writeObjects(pasteboardItems)
    }
  }

  /// Stages and pastes one finalized result, leaving the text on the clipboard.
  ///
  /// The insert-and-copy destination skips the snapshot and the restore on
  /// purpose: the text staying on the clipboard is what the user asked for,
  /// so there is nothing to put back and no acquisition budget to spend.
  ///
  /// - Parameters:
  ///   - text: The finalized text to insert and keep on the clipboard.
  ///   - target: The validated focus boundary that should receive the paste.
  /// - Returns: The terminal delivery outcome after all safe fallbacks.
  func pasteLeavingClipboard(
    _ text: String,
    into target: Target
  ) async -> InsertionOutcome {
    guard stageClipboardText(
      text,
      ifUnchangedSince: dependencies.pasteboard.changeCount
    ) != nil else { return .unavailable }

    guard dependencies.postPasteShortcut() else {
      // The paste never fired, but the text is already on the clipboard,
      // which is exactly the manual-paste fallback.
      return .copiedToClipboard
    }
    await dependencies.waitForPasteRead()
    return .inserted
  }

  /// Places finalized text on the clipboard when no target paste is safe.
  ///
  /// - Parameter text: The finalized text to retain for manual paste.
  /// - Returns: `.copiedToClipboard`, or `.unavailable` while a reader owns the
  ///   pasteboard lease and any same-instance write would be unsafe.
  func copyToClipboard(_ text: String) -> InsertionOutcome {
    guard !isClipboardReadActive() else { return .unavailable }

    let pasteboard = dependencies.pasteboard
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
    return .copiedToClipboard
  }

  /// Reports whether an actual background pasteboard read still owns the lease.
  ///
  /// - Returns: `true` until the reader closure returns, even after timeout.
  private func isClipboardReadActive() -> Bool {
    clipboardReadLease.withLock { $0 }
  }
}
