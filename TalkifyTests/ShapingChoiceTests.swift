import Testing
@testable import Talkify

/// Pins what the HUD's shaping band draws to either side of the pick. The
/// band has no arrow glyphs, so a wrong neighbour is an arrow pointing at the
/// wrong prompt.
struct ShapingChoiceTests {
  private static func choice(
    _ library: [ShapingPrompt],
    selecting index: Int?
  ) -> ShapingChoice? {
    ShapingChoice(
      library: library,
      selected: index.map { library[$0] }
    )
  }

  @Test func anEmptyLibraryCannotCycle() {
    #expect(ShapingChoice(library: [], selected: nil) == nil)
  }

  @Test func theNoneOptionClosesTheCycle() {
    let library = ShapingPrompt.defaults
    let choice = Self.choice(library, selecting: nil)
    #expect(choice?.options == library.map(\.name) + ["None"])
    #expect(choice?.current == "None")
  }

  @Test func neighboursAreThePicksTheArrowsWouldLand() {
    let library = ShapingPrompt.defaults
    let choice = Self.choice(library, selecting: 1)
    #expect(choice?.current == library[1].name)
    #expect(choice?.previous == library[0].name)
    #expect(choice?.next == library[2].name)
  }

  @Test func bothEndsWrapTheWayCyclingDoes() {
    let library = ShapingPrompt.defaults
    let first = Self.choice(library, selecting: 0)
    #expect(first?.previous == "None")
    let none = Self.choice(library, selecting: nil)
    #expect(none?.next == library[0].name)
    #expect(none?.previous == library[library.count - 1].name)
  }

  /// One prompt leaves two options, so both arrows land on the same one.
  @Test func aSinglePromptPutsTheSameOptionOnBothSides() {
    let library = [ShapingPrompt.defaults[0]]
    let choice = Self.choice(library, selecting: 0)
    #expect(choice?.previous == "None")
    #expect(choice?.next == "None")
  }

  /// The same rule the insertion path follows: a pick the library no longer
  /// carries is passthrough, so the band has to show None rather than a name
  /// nothing will shape with.
  @Test func aDeletedPickShowsAsNone() {
    let library = ShapingPrompt.defaults
    let deleted = ShapingPrompt(
      id: "gone",
      name: "Gone",
      preInstruction: "",
      postInstruction: "",
      exampleInput: "",
      exampleOutput: ""
    )
    let choice = ShapingChoice(library: library, selected: deleted)
    #expect(choice?.current == "None")
  }

  @Test func theDirectionRidesAlongUntouched() {
    let library = ShapingPrompt.defaults
    #expect(ShapingChoice(library: library, selected: nil)?.direction == 0)
    #expect(
      ShapingChoice(library: library, selected: nil, direction: -1)?.direction == -1
    )
  }
}
