import AppKit
import Testing
@testable import Talkify

/// Where a finished session's text goes. The default still pastes and puts the
/// clipboard back; the other two picks exist for people that fights.
@MainActor
struct InsertionDestinationTests {
  private func pasteboard() -> NSPasteboard {
    NSPasteboard(name: .init(rawValue: "TalkifyTests-destination-\(UUID().uuidString)"))
  }

  /// Named test pasteboards are isolated to one test, but AppKit does not
  /// declare NSPasteboard Sendable for this background-capable API.
  private nonisolated func reader(
    for pasteboard: NSPasteboard
  ) -> @Sendable () -> [TextInsertionService.ClipboardItemSnapshot]? {
    nonisolated(unsafe) let background = pasteboard
    return { TextInsertionService.snapshot(of: background) }
  }

  /// A flag the paste closures can set from whatever context they run on.
  private final class Signal: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String?
    private var fired = false

    func fire(_ value: String? = nil) {
      lock.lock()
      fired = true
      stored = value
      lock.unlock()
    }

    var didFire: Bool {
      lock.lock()
      defer { lock.unlock() }
      return fired
    }

    var value: String? {
      lock.lock()
      defer { lock.unlock() }
      return stored
    }
  }

  private func service(
    _ board: NSPasteboard,
    isTargetFocused: @escaping @Sendable (TextInsertionService.Target) -> Bool = { _ in true },
    postPasteShortcut: @escaping @Sendable () -> Bool = { true },
    onPaste: @escaping @Sendable () -> Void = {}
  ) -> TextInsertionService {
    TextInsertionService(dependencies: .init(
      pasteboard: board,
      readClipboardItems: reader(for: board),
      snapshotTimeout: .milliseconds(100),
      focusedElement: { nil },
      frontmostApplication: { nil },
      isProcessRunning: { _ in true },
      isTargetFocused: isTargetFocused,
      postPasteShortcut: postPasteShortcut,
      waitForPasteRead: { onPaste() }
    ))
  }

  private func target() -> TextInsertionService.Target {
    TextInsertionService.Target(
      element: nil,
      processIdentifier: ProcessInfo.processInfo.processIdentifier,
      isSecure: false,
      displayID: nil
    )
  }

  /// Clipboard-only never pastes, so the words stay where the user can place
  /// them and the previous clipboard is not put back over them.
  @Test func clipboardOnlyLeavesTheTextAndPastesNothing() async {
    let board = pasteboard()
    board.clearContents()
    board.setString("previous clipboard", forType: .string)
    let pasted = Signal()
    let service = service(board, postPasteShortcut: { pasted.fire(); return true })

    let outcome = await service.insert("dictated", into: target(), destination: .clipboard)

    #expect(outcome == .copiedToClipboard)
    #expect(!pasted.didFire)
    #expect(board.string(forType: .string) == "dictated")
  }

  /// It returns before any target check, because there is no control to paste
  /// into: a dead target must not turn a clipboard-only session into a failure.
  @Test func clipboardOnlyDoesNotNeedALiveTarget() async {
    let board = pasteboard()
    board.clearContents()
    let service = service(board, isTargetFocused: { _ in false })

    let outcome = await service.insert("dictated", into: nil, destination: .clipboard)

    #expect(outcome == .copiedToClipboard)
    #expect(board.string(forType: .string) == "dictated")
  }

  /// The point of insert-and-copy: the words are still on the clipboard
  /// afterwards, which is what lets a history manager keep them.
  @Test func insertAndCopyPastesAndKeepsTheTextOnTheClipboard() async {
    let board = pasteboard()
    board.clearContents()
    board.setString("previous clipboard", forType: .string)
    let seen = Signal()
    nonisolated(unsafe) let background = board
    let service = service(board, onPaste: { seen.fire(background.string(forType: .string)) })

    let outcome = await service.insert("dictated", into: target(), destination: .insertAndCopy)

    #expect(outcome == .inserted)
    #expect(seen.value == "dictated")
    #expect(board.string(forType: .string) == "dictated")
  }

  /// The default is unchanged: paste, then put the clipboard back.
  @Test func insertingStillRestoresThePreviousClipboard() async {
    let board = pasteboard()
    board.clearContents()
    board.setString("previous clipboard", forType: .string)
    let service = service(board)

    let outcome = await service.insert("dictated", into: target(), destination: .insert)

    #expect(outcome == .inserted)
    #expect(board.string(forType: .string) == "previous clipboard")
  }

  /// Insert-and-copy with a target that went away still leaves the words on
  /// the clipboard, which is the outcome that counts as a finished session.
  @Test func insertAndCopyFallsBackToTheClipboardWhenThePasteFails() async {
    let board = pasteboard()
    board.clearContents()
    let service = service(board, postPasteShortcut: { false })

    let outcome = await service.insert("dictated", into: target(), destination: .insertAndCopy)

    #expect(outcome == .copiedToClipboard)
    #expect(board.string(forType: .string) == "dictated")
  }

  @Test func theDefaultPickIsTodaysBehaviour() {
    #expect(InsertionDestination.insert.pastes)
    #expect(InsertionDestination.insert.restoresClipboard)
    #expect(!InsertionDestination.clipboard.pastes)
    #expect(InsertionDestination.insertAndCopy.pastes)
    #expect(!InsertionDestination.insertAndCopy.restoresClipboard)
  }
}
