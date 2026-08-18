import Foundation

/// The draft and the selection a replacement round began with — the round's
/// whole contract in one value.
///
/// While the round listens, its streaming words preview into that exact
/// spot (the band keeps showing the held draft with the words spliced over
/// the selection, never the words alone); when it delivers, they commit
/// over the selection; when it delivers nothing, the draft comes back
/// untouched. Pure, so these rules are pinned by DraftReplacementTests
/// instead of living as unseeable sides of the controller.
struct DraftReplacement {
  let draft: String
  let range: NSRange

  /// The text the band shows for a live update: a fresh round streams the
  /// recognized words alone, as dictation always did; a replacement round
  /// keeps its held draft on screen with the words spliced over the
  /// selection.
  static func liveBandText(replacement: DraftReplacement?, liveText: String) -> String {
    replacement?.preview(liveText: liveText) ?? liveText
  }

  /// The held draft with the round's streaming words spliced over the
  /// selection — the live in-place replacement preview. Before any words
  /// arrive the draft shows whole, exactly as the user last edited or left
  /// it, so the selection it is about to overwrite stays on screen too.
  /// Whitespace-only hypotheses (speech starting, trailing silence) leave
  /// the draft whole as well.
  func preview(liveText: String) -> String {
    if !hasWords(liveText) { return draft }
    guard let selected = Range(range, in: draft) else { return draft }
    return draft.replacingCharacters(in: selected, with: liveText)
  }

  /// The committed draft once the round delivers: its text replaces the
  /// selection. A round that delivered nothing (or only whitespace) leaves
  /// the draft untouched.
  func committed(with text: String) -> String {
    if !hasWords(text) { return draft }
    guard let selected = Range(range, in: draft) else { return draft }
    return draft.replacingCharacters(in: selected, with: text)
  }

  /// Whether the round's recognized text actually contains words: speech
  /// that never produced a word (trailing silence, a release with nothing
  /// said) leaves the draft untouched instead of deleting the selection.
  func hasWords(_ text: String) -> Bool {
    !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  /// The UTF-16 offset in the committed draft just after the inserted
  /// words — where the review's cursor should land when the field returns.
  func insertionPointOffset(committing text: String) -> Int {
    guard let selected = Range(range, in: draft) else { return draft.utf16.count }
    return selected.lowerBound.utf16Offset(in: draft) + text.utf16.count
  }
}
