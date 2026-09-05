import CoreGraphics
import Testing

@testable import Talkify

@Suite("Recent draft window")
struct HUDRecentDraftWindowTests {
  @Test func fewerThanEightTokensStayWhole() {
    let window = HUDRecentDraftWindow(
      committed: "one two three",
      volatile: " four"
    )
    #expect(window.committed == "one two three")
    #expect(window.volatile == " four")
    #expect(window.displayString == "one two three four")
    #expect(window.evictionOffset == 0)
    #expect(window.tokenCount == 4)
  }

  @Test func exactlyEightTokensStayWhole() {
    let window = HUDRecentDraftWindow(
      committed: "one two three four five six seven eight",
      volatile: ""
    )
    #expect(window.committed == "one two three four five six seven eight")
    #expect(window.volatile.isEmpty)
    #expect(window.evictionOffset == 0)
    #expect(window.tokenCount == 8)
  }

  @Test func theNinthTokenEvictsTheFirst() {
    let window = HUDRecentDraftWindow(
      committed: "one two three four five six seven eight nine",
      volatile: ""
    )
    #expect(window.committed == "two three four five six seven eight nine")
    #expect(window.volatile.isEmpty)
    #expect(window.evictionOffset > 0)
    #expect(window.tokenCount == 9)
  }

  @Test func aPartialVolatileTokenCountsAsOneWord() {
    let window = HUDRecentDraftWindow(
      committed: "one two three four five six seven ",
      volatile: "eigh"
    )
    #expect(window.committed == "one two three four five six seven ")
    #expect(window.volatile == "eigh")
    #expect(window.evictionOffset == 0)
    #expect(window.tokenCount == 8)
  }

  @Test func aVolatileTokenCanCrossTheEvictionBoundary() {
    let window = HUDRecentDraftWindow(
      committed: "one two three four five six seven eight ",
      volatile: "nine"
    )
    #expect(window.committed == "two three four five six seven eight ")
    #expect(window.volatile == "nine")
    #expect(window.evictionOffset > 0)
    #expect(window.tokenCount == 9)
  }

  @Test func punctuationAndSpacesStayInsideTheSuffix() {
    let window = HUDRecentDraftWindow(
      committed: "Hello, world. This is a longer line, yes it is.",
      volatile: ""
    )
    #expect(window.committed.hasPrefix("This"))
    #expect(window.committed.contains("line,"))
    #expect(!window.committed.contains("Hello"))
  }

  @Test func aStringWithNoWordTokensIsUnchanged() {
    let window = HUDRecentDraftWindow(committed: "— —", volatile: " !!!")
    #expect(window.committed == "— —")
    #expect(window.volatile == " !!!")
    #expect(window.evictionOffset == 0)
    #expect(window.tokenCount == 0)
  }

  @Test func emptyInputIsEmpty() {
    let window = HUDRecentDraftWindow(committed: "", volatile: "")
    #expect(window.committed.isEmpty)
    #expect(window.volatile.isEmpty)
    #expect(window.evictionOffset == 0)
    #expect(window.tokenCount == 0)
  }

  @Test func aNewTokenAdvancesAndAnInTokenRewriteDoesNot() {
    let two = HUDRecentDraftWindow(committed: "one two", volatile: "")
    let three = HUDRecentDraftWindow(committed: "one two ", volatile: "thr")
    let threeRewritten = HUDRecentDraftWindow(committed: "one two ", volatile: "three")
    let four = HUDRecentDraftWindow(committed: "one two three four", volatile: "")
    #expect(three.advances(from: two))
    #expect(!threeRewritten.advances(from: three))
    #expect(four.advances(from: threeRewritten))
  }

  @Test func theNinthTokenAdvancesByEviction() {
    let eight = HUDRecentDraftWindow(
      committed: "one two three four five six seven eight",
      volatile: ""
    )
    let nine = HUDRecentDraftWindow(
      committed: "one two three four five six seven eight nine",
      volatile: ""
    )
    #expect(nine.advances(from: eight))
  }

  @Test func aBackwardRewriteDoesNotAdvance() {
    let three = HUDRecentDraftWindow(committed: "one two three", volatile: "")
    let two = HUDRecentDraftWindow(committed: "one two", volatile: "")
    #expect(!two.advances(from: three))
  }

  @Test func visibleTokensKeepStableIDsAcrossAnEviction() {
    let eight = HUDRecentDraftWindow(
      committed: "one two three four five six seven eight",
      volatile: ""
    )
    let nine = HUDRecentDraftWindow(
      committed: "one two three four five six seven eight nine",
      volatile: ""
    )
    #expect(eight.visibleTokens.map(\.id) == [0, 1, 2, 3, 4, 5, 6, 7])
    #expect(nine.visibleTokens.map(\.id) == [1, 2, 3, 4, 5, 6, 7, 8])
    #expect(eight.visibleTokens.map(\.text).joined() == eight.displayString)
    #expect(nine.visibleTokens.map(\.text).joined() == nine.displayString)
  }

  @Test func aFinalizationKeepsTheSameTokenID() {
    let guessing = HUDRecentDraftWindow(
      committed: "one two three four five six seven ",
      volatile: "eigh"
    )
    let finalized = HUDRecentDraftWindow(
      committed: "one two three four five six seven eight",
      volatile: ""
    )
    #expect(guessing.tokenIDs == finalized.tokenIDs)
    #expect(guessing.tokenIDs.count == 8)
  }

  @Test func anInTokenRewriteKeepsTheSameTokenID() {
    let partial = HUDRecentDraftWindow(committed: "one two ", volatile: "thr")
    let longer = HUDRecentDraftWindow(committed: "one two ", volatile: "three")
    #expect(partial.tokenIDs == longer.tokenIDs)
  }

  /// Apple Speech can merge a volatile `can not` into a final `cannot`.
  /// Token count drops and the window's ids reshuffle; that must snap, not
  /// play the new-word slide.
  @Test func aMergingFinalizationDoesNotAdvance() {
    let guessing = HUDRecentDraftWindow(
      committed: "one two three four five six seven ",
      volatile: "can not"
    )
    let finalized = HUDRecentDraftWindow(
      committed: "one two three four five six seven cannot",
      volatile: ""
    )
    #expect(guessing.tokenIDs == [1, 2, 3, 4, 5, 6, 7, 8])
    #expect(finalized.tokenIDs == [0, 1, 2, 3, 4, 5, 6, 7])
    #expect(!finalized.advances(from: guessing))
  }

  @Test func aSplittingFinalizationAdvances() {
    let guessing = HUDRecentDraftWindow(
      committed: "one two three four five six seven ",
      volatile: "cannot"
    )
    let finalized = HUDRecentDraftWindow(
      committed: "one two three four five six seven can not",
      volatile: ""
    )
    #expect(guessing.tokenIDs == [0, 1, 2, 3, 4, 5, 6, 7])
    #expect(finalized.tokenIDs == [1, 2, 3, 4, 5, 6, 7, 8])
    #expect(finalized.advances(from: guessing))
  }
}

@Suite("Recent draft line overflow")
struct HUDRecentDraftLineTests {
  @Test func aLineThatFitsIsCentered() {
    let bounds = CGRect(x: 10, y: 0, width: 100, height: 40)
    #expect(HUDRecentDraftLine.originX(contentWidth: 40, in: bounds) == 40)
  }

  @Test func aLineThatOverflowsKeepsTheTrailingEdge() {
    let bounds = CGRect(x: 10, y: 0, width: 100, height: 40)
    #expect(HUDRecentDraftLine.originX(contentWidth: 140, in: bounds) == -30)
  }
}
