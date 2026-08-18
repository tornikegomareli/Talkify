import ApplicationServices
import Testing
@testable import Talkify

/// What Read Aloud is allowed to speak. Direct Dictation already refuses a
/// secure field and says so; speech goes into the room, so this path has to
/// refuse the same fields rather than reading a password out loud.
@MainActor
struct FocusedSelectionReaderTests {
  private func reader(
    subrole: String? = nil,
    selectedText: String? = nil,
    focused: Bool = true
  ) -> FocusedSelectionReader {
    FocusedSelectionReader(
      dependencies: .init(
        focus: {
          guard focused else { return nil }
          return .init(subrole: subrole, selectedText: selectedText)
        }
      )
    )
  }

  @Test func aSecureFieldIsRefusedEvenWhenItHasASelection() {
    let secure = reader(
      subrole: kAXSecureTextFieldSubrole as String,
      selectedText: "hunter2"
    )
    #expect(secure.selection() == .secureField)
  }

  @Test func anOrdinarySelectionIsSpoken() {
    #expect(reader(subrole: "AXStandardWindow", selectedText: "hello").selection()
      == .text("hello"))
    #expect(reader(selectedText: "no subrole reported").selection()
      == .text("no subrole reported"))
  }

  /// Whitespace is not a selection worth speaking, and it must not be
  /// mistaken for one now that the empty case also covers "nothing focused".
  @Test func blankAndMissingSelectionsBothReadAsNone() {
    #expect(reader(selectedText: nil).selection() == .none)
    #expect(reader(selectedText: "").selection() == .none)
    #expect(reader(selectedText: "  \n\t ").selection() == .none)
    #expect(reader(focused: false).selection() == .none)
  }

  /// The secure check runs before the selection check, so a secure field with
  /// nothing selected still reports as secure rather than as empty.
  @Test func anEmptySecureFieldStillReportsSecure() {
    let secure = reader(subrole: kAXSecureTextFieldSubrole as String, selectedText: nil)
    #expect(secure.selection() == .secureField)
  }
}
