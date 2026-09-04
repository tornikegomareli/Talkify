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
    #expect(window.evictionOffset == 0)
  }

  @Test func exactlyEightTokensStayWhole() {
    let window = HUDRecentDraftWindow(
      committed: "one two three four five six seven eight",
      volatile: ""
    )
    #expect(window.committed == "one two three four five six seven eight")
    #expect(window.volatile.isEmpty)
    #expect(window.evictionOffset == 0)
  }

  @Test func theNinthTokenEvictsTheFirst() {
    let window = HUDRecentDraftWindow(
      committed: "one two three four five six seven eight nine",
      volatile: ""
    )
    #expect(window.committed == "two three four five six seven eight nine")
    #expect(window.volatile.isEmpty)
    #expect(window.evictionOffset > 0)
  }

  @Test func aPartialVolatileTokenCountsAsOneWord() {
    let window = HUDRecentDraftWindow(
      committed: "one two three four five six seven ",
      volatile: "eigh"
    )
    #expect(window.committed == "one two three four five six seven ")
    #expect(window.volatile == "eigh")
    #expect(window.evictionOffset == 0)
  }

  @Test func aVolatileTokenCanCrossTheEvictionBoundary() {
    let window = HUDRecentDraftWindow(
      committed: "one two three four five six seven eight ",
      volatile: "nine"
    )
    #expect(window.committed == "two three four five six seven eight ")
    #expect(window.volatile == "nine")
    #expect(window.evictionOffset > 0)
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
  }

  @Test func emptyInputIsEmpty() {
    let window = HUDRecentDraftWindow(committed: "", volatile: "")
    #expect(window.committed.isEmpty)
    #expect(window.volatile.isEmpty)
    #expect(window.evictionOffset == 0)
  }
}
