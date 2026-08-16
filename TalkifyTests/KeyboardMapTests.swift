import SwiftUI
import Testing

@testable import Talkify

/// The rows drawn for each keyboard shape. What separates ANSI from ISO is
/// which keycodes appear where, so that is what is asserted here rather than
/// anything about pixels.
@Suite("Keyboard map")
struct KeyboardMapTests {
  private func keyCodes(_ shape: KeyboardLayout.Shape, row: Int) -> [Int64] {
    KeyboardMap.rows(for: shape)[row].map(\.keyCode)
  }

  /// The ISO signature: § sits left of 1 where ANSI has the backtick, and the
  /// backtick moves down beside left ⇧. Getting this backwards draws a board
  /// nobody owns.
  @Test func isoMovesTheBacktickBesideLeftShift() {
    #expect(keyCodes(.ansi, row: 1).first == 50)
    #expect(keyCodes(.iso, row: 1).first == 10)

    #expect(!keyCodes(.ansi, row: 4).contains(50))
    #expect(keyCodes(.iso, row: 4).contains(50))
  }

  /// ANSI ends the upper row with the backslash; ISO gives that row to Return,
  /// which runs down through the home row too.
  @Test func isoReturnSpansTwoRows() {
    #expect(keyCodes(.ansi, row: 2).last == 42)
    #expect(!keyCodes(.ansi, row: 2).contains(36))

    #expect(keyCodes(.iso, row: 2).contains(36))
    #expect(keyCodes(.iso, row: 3).contains(36))
    #expect(keyCodes(.iso, row: 3).contains(42))
  }

  /// Every shape still has to offer the keys a binding can name, or a bound
  /// key would have nowhere to light up.
  @Test(arguments: [KeyboardLayout.Shape.ansi, .iso, .jis])
  func everyShapeDrawsTheModifiersAndLetters(shape: KeyboardLayout.Shape) {
    let all = Set(KeyboardMap.rows(for: shape).flatMap { $0.map(\.keyCode) })
    for modifier in [63, 59, 58, 55, 54, 61, 56, 60] {
      #expect(all.contains(Int64(modifier)), "shape \(shape) is missing keycode \(modifier)")
    }
    for letter in [12, 0, 6, 49, 53, 36] {
      #expect(all.contains(Int64(letter)), "shape \(shape) is missing keycode \(letter)")
    }
  }

  /// No keycode is drawn twice in one row, which would be a duplicated cap.
  @Test(arguments: [KeyboardLayout.Shape.ansi, .iso, .jis])
  func noRowRepeatsAKey(shape: KeyboardLayout.Shape) {
    for row in KeyboardMap.rows(for: shape) {
      let codes = row.map(\.keyCode)
      #expect(codes.count == Set(codes).count, "a row repeats a keycode in \(shape)")
    }
  }

  /// A binding lights its own key plus both sides of each modifier it needs,
  /// because either one satisfies it.
  @Test func aComboLightsItsKeyAndBothSidesOfItsModifiers() {
    let fnOption = KeyBinding(
      keyCode: 63,
      modifierFlags: CGEventFlags.maskAlternate.rawValue,
      isModifierKey: true,
      label: "⌥ fn",
      keyEquivalent: ""
    )
    #expect(KeyboardMap.highlighted(for: fnOption) == [63, 58, 61])
    #expect(KeyboardMap.highlighted(for: .fnTrigger) == [63])
    #expect(KeyboardMap.highlighted(for: .optionEscape) == [53, 58, 61])
  }

  /// Legends are only read for keys whose cap the input source can change; a
  /// key drawn without a fixed glyph must be in that list or it renders blank.
  @Test func everyLegendKeyIsRequestedFromTheLayout() {
    let requested = Set(KeyboardMap.legendKeyCodes)
    for shape in [KeyboardLayout.Shape.ansi, .iso, .jis] {
      for row in KeyboardMap.rows(for: shape) {
        for key in row where key.glyph == nil {
          #expect(requested.contains(key.keyCode), "keycode \(key.keyCode) has no legend source")
        }
      }
    }
  }
}

/// Reading the real keyboard. These touch the live system, so they assert the
/// shape of the answer rather than a particular machine's value.
@Suite("Keyboard layout reading")
struct KeyboardLayoutTests {
  @Test func theCurrentLayoutReportsAShapeAndLegends() {
    let layout = KeyboardLayout.current()
    #expect([.ansi, .iso, .jis].contains(layout.shape))

    // Q on QWERTY, A on AZERTY, ქ in Georgian — whatever this Mac is set to,
    // the letter keys have to come back with something on them.
    let letters = [12, 13, 14, 0, 1, 2].compactMap { layout.legend(for: Int64($0)) }
    #expect(letters.count == 6, "the layout produced no legend for a letter key")
    #expect(letters.allSatisfy { !$0.isEmpty })
  }

  @Test func legendsAreUppercasedLikeAKeycap() {
    let layout = KeyboardLayout(shape: .ansi, legends: [12: "q", 13: "w"])
    #expect(layout.legend(for: 12) == "Q")
    #expect(layout.legend(for: 99) == nil)
  }
}
