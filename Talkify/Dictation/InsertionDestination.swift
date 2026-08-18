import Foundation

/// Where a finished Direct Dictation session's text goes.
///
/// Pasting and restoring the clipboard is right for most people and stays the
/// default, but it fights two real cases: someone who wants to place the text
/// themselves rather than have it land wherever focus happened to sit, and
/// anyone running a clipboard-history manager, whose history never keeps a
/// dictation because the restore puts the old clipboard back over it.
///
/// The raw values are persisted picks and are load-bearing (CLAUDE.md).
enum InsertionDestination: String, CaseIterable, Sendable {
  /// Paste into the focused control, then put the previous clipboard back.
  case insert
  /// Leave the text on the clipboard and paste nothing.
  case clipboard
  /// Paste into the focused control and deliberately leave the text on the
  /// clipboard, so a history manager keeps it.
  case insertAndCopy

  var title: String {
    switch self {
    case .insert: "Insert into the app"
    case .clipboard: "Copy to the clipboard"
    case .insertAndCopy: "Insert and copy"
    }
  }

  var detail: String {
    switch self {
    case .insert: "Paste where you were typing, then restore your clipboard"
    case .clipboard: "Never paste. Leave the words on the clipboard for you to place"
    case .insertAndCopy: "Paste where you were typing and keep the words on the clipboard"
    }
  }

  /// Whether the session has a focused control to paste into. Clipboard-only
  /// has no target, so it never validates one.
  var pastes: Bool { self != .clipboard }

  /// Whether the previous clipboard is put back afterwards. Insert-and-copy
  /// exists precisely to leave it alone.
  var restoresClipboard: Bool { self == .insert }
}
