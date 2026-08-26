import Testing
@testable import Talkify

struct FillerWordFilterTests {
  private let filter = FillerWordFilter()

  @Test func leadingAndTrailingFillersAreRemoved() {
    #expect(filter.filter("Uhmm, write the note ahh") == "Write the note")
  }

  @Test func aLeadingFillerCapitalizesTheFirstRemainingWord() {
    #expect(filter.filter("Uhhh, hello") == "Hello")
  }

  @Test func fillersBetweenWordsLeaveTheWordsIntact() {
    #expect(filter.filter("Send, mhmm, the report") == "Send, the report")
  }

  @Test func repeatedFillersCollapseToOneSpace() {
    #expect(filter.filter("Hello umm uhmm world") == "Hello world")
  }

  @Test func punctuatedFillerProducesNoText() {
    #expect(filter.filter("Ahh...").isEmpty)
  }

  @Test func ordinaryWordsAreUnchanged() {
    #expect(filter.filter("A hummingbird visits at noon.") == "A hummingbird visits at noon.")
  }
}
