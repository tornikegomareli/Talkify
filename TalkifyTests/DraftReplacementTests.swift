import Foundation
import Testing
@testable import Talkify

/// Pins what the band shows during a dictation round. The second
/// live-test bug — a replacement round replaced the held draft with the
/// live words alone — lived in the controller's text routing, so the
/// preview/commit rules are extracted into a value and locked here:
/// a replacement round always keeps the full draft on screen with the
/// streaming words spliced over the selection, and a fresh round still
/// shows the recognized words alone.
struct DraftReplacementTests {
  private func replacement(_ draft: String, _ location: Int, _ length: Int) -> DraftReplacement {
    DraftReplacement(draft: draft, range: NSRange(location: location, length: length))
  }

  @Test func freshRoundStreamsTheWordsAlone() {
    // No replacement context: the band shows the recognized words only,
    // exactly as the ordinary flow always has.
    #expect(DraftReplacement.liveBandText(replacement: nil, liveText: "hello there") == "hello there")
    #expect(DraftReplacement.liveBandText(replacement: nil, liveText: "the quick brown") == "the quick brown")
  }

  @Test func replacementRoundKeepsTheDraftWithWordsSplicedAtTheSelection() {
    // The reported bug: the band showed only the new words. It must show
    // the full draft with the words landing where the selection was.
    let round = replacement("the quick fox jumps", 10, 3)
    #expect(
      DraftReplacement.liveBandText(replacement: round, liveText: "brown")
        == "the quick brown jumps"
    )
  }

  @Test func replacementRoundSplicesAsTheHypothesisStreams() {
    let round = replacement("I like the draft", 2, 4)
    #expect(DraftReplacement.liveBandText(replacement: round, liveText: "lo") == "I lo the draft")
    #expect(DraftReplacement.liveBandText(replacement: round, liveText: "love") == "I love the draft")
  }

  @Test func replacementPreviewShowsTheDraftWholeBeforeAnyWordsArrive() {
    let round = replacement("the quick fox jumps", 10, 3)
    #expect(round.preview(liveText: "") == "the quick fox jumps")
    #expect(
      DraftReplacement.liveBandText(replacement: round, liveText: "  ")
        == "the quick fox jumps"
    )
  }

  @Test func replacementPreviewNeverDropsTheRestOfTheDraft() {
    let round = replacement("read the whole sentence carefully", 9, 5)
    for live in ["wor", "words"] {
      let shown = DraftReplacement.liveBandText(replacement: round, liveText: live)
      #expect(shown.hasPrefix("read the "))
      #expect(shown.hasSuffix(" sentence carefully"))
      #expect(shown.contains(live))
    }
  }

  @Test func commitReplacesExactlyTheSelection() {
    let round = replacement("the quick fox jumps", 10, 3)
    #expect(round.committed(with: "slow") == "the quick slow jumps")
  }

  @Test func commitWithNoWordsLeavesTheDraftUntouched() {
    let round = replacement("the quick fox jumps", 10, 3)
    #expect(round.committed(with: "") == "the quick fox jumps")
    // Trailing silence/whitespace is no words: the selection survives.
    #expect(round.committed(with: "   ") == "the quick fox jumps")
    #expect(!round.hasWords("   "))
  }

  @Test func insertionPointLandsAfterTheInsertedWords() {
    let round = replacement("the quick fox jumps", 10, 3)
    let draft = round.committed(with: "brown")
    let cursor = String.Index(utf16Offset: round.insertionPointOffset(committing: "brown"), in: draft)
    #expect(String(draft[cursor...]) == " jumps")
    #expect(draft[draft.index(before: cursor)] == "n")
  }

  @Test func replacementHighlightMarksTheSelectionBeforeAnyWordsArrive() {
    // The bug: while a replacement round listened, the streaming draft
    // rendered with no visible mark of the range being replaced. The
    // selection itself must be the highlighted landing zone before any
    // words stream.
    let round = replacement("the quick fox jumps", 10, 3)
    #expect(round.highlightRange(liveText: "") == NSRange(location: 10, length: 3))
    #expect(round.highlightRange(liveText: "   ") == NSRange(location: 10, length: 3))
  }

  @Test func replacementHighlightTracksTheStreamingWordsInPlace() throws {
    // Once words arrive they occupy exactly the selection's position, and
    // the highlight follows them so the landing zone never blinks away.
    let round = replacement("the quick fox jumps", 10, 3)
    #expect(round.highlightRange(liveText: "brown") == NSRange(location: 10, length: 5))
    #expect(round.highlightRange(liveText: "bro") == NSRange(location: 10, length: 3))
    // The highlight sits in the same preview the band shows: it highlights
    // the "brown" the preview splices in.
    let preview = round.preview(liveText: "brown")
    let span = try #require(Range(round.highlightRange(liveText: "brown"), in: preview))
    #expect(String(preview[span]) == "brown")
  }

  @Test func outOfBoundsSelectionLeavesTheDraftUntouched() {
    let round = replacement("short", 50, 3)
    #expect(round.preview(liveText: "x") == "short")
    #expect(round.committed(with: "x") == "short")
  }
}
