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

  /// One cap per physical key, modifiers first in the order macOS writes them.
  @Test func aBindingBecomesOneCapPerKey() {
    let layout = KeyboardLayout(shape: .ansi, legends: [35: "p"])
    let shiftP = KeyBinding(
      keyCode: 35,
      modifierFlags: CGEventFlags.maskShift.rawValue,
      isModifierKey: false,
      label: "⇧ P",
      keyEquivalent: "p"
    )
    #expect(KeyboardMap.caps(for: shiftP, layout: layout) == ["⇧", "P"])
    #expect(KeyboardMap.caps(for: .optionEscape, layout: layout) == ["⌥", "esc"])
    #expect(KeyboardMap.caps(for: .fnTrigger, layout: layout) == ["fn"])
  }

  @Test func aMouseBindingGetsACapWithoutInventingAKeyboardKey() throws {
    let layout = KeyboardLayout(shape: .ansi, legends: [:])
    let middleClick = try #require(KeyBinding.mouseButton(number: 2))
    let optionMouseFour = try #require(KeyBinding.mouseButton(number: 3, modifiers: [.option]))

    #expect(KeyboardMap.caps(for: middleClick, layout: layout) == ["Middle"])
    #expect(KeyboardMap.highlighted(for: middleClick).isEmpty)
    #expect(KeyboardMap.caps(for: optionMouseFour, layout: layout) == ["⌥", "Mouse 4"])
    #expect(KeyboardMap.highlighted(for: optionMouseFour) == [58, 61])
  }

  /// Modifiers read in the order macOS prints them, whichever order they were
  /// held in while recording.
  @Test func modifierCapsAreOrderedTheWayMacOSWritesThem() {
    let everything = KeyBinding(
      keyCode: 49,
      modifierFlags: CGEventFlags([.maskCommand, .maskShift, .maskAlternate, .maskControl])
        .rawValue,
      isModifierKey: false,
      label: "",
      keyEquivalent: " "
    )
    let caps = KeyboardMap.caps(for: everything, layout: KeyboardLayout(shape: .ansi, legends: [:]))
    #expect(caps == ["⌃", "⌥", "⇧", "⌘", "space"])
  }

  /// A key the input source has no legend for still gets a cap rather than a
  /// blank one, so a row never renders an empty square.
  @Test func anUnknownKeyStillGetsACap() {
    let odd = KeyBinding(
      keyCode: 999, modifierFlags: 0, isModifierKey: false, label: "", keyEquivalent: ""
    )
    #expect(KeyboardMap.caps(for: odd, layout: KeyboardLayout(shape: .ansi, legends: [:])) == ["?"])
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

/// Building a binding by clicking keys on the drawn keyboard. This is the path
/// that can assign a combination the recorder cannot capture, because the
/// system or another app swallows it before Talkify sees it.
@Suite("Binding by clicking")
struct ClickToBindTests {
  private let layout = KeyboardLayout(shape: .ansi, legends: [35: "p", 12: "q"])

  /// A modifier waits for the rest of the combination; anything else finishes
  /// it. This is what makes ⌥ then fn reachable by clicking.
  @Test func aModifierWaitsAndAnythingElseFinishes() {
    #expect(ShortcutAssignment.click(58, picked: []) == .picking([58]))
    #expect(ShortcutAssignment.click(63, picked: [58]) == .complete([58, 63]))
    #expect(ShortcutAssignment.click(35, picked: []) == .complete([35]))
  }

  /// Clicking a held modifier again lets it go, so a mis-click is undoable
  /// without starting the selection over.
  @Test func clickingAHeldModifierAgainLetsItGo() {
    #expect(ShortcutAssignment.click(58, picked: [58]) == .picking([]))
    #expect(ShortcutAssignment.click(58, picked: [56, 58]) == .picking([56]))
    #expect(ShortcutAssignment.click(56, picked: [56, 58]) == .picking([58]))
  }

  @Test func aModifierThenAKeyBecomesACombo() {
    let binding = ShortcutAssignment.binding(forClicked: [58, 63], layout: layout)
    #expect(binding?.keyCode == 63)
    #expect(binding?.modifiers == .maskAlternate)
    #expect(binding?.isModifierKey == true)
    #expect(binding?.label == "⌥ fn")
  }

  @Test func aLetterWithModifiersKeepsTheLetterAsTheKey() {
    let binding = ShortcutAssignment.binding(forClicked: [56, 35], layout: layout)
    #expect(binding?.keyCode == 35)
    #expect(binding?.modifiers == .maskShift)
    #expect(binding?.isModifierKey == false)
    #expect(binding?.keyEquivalent == "p")
  }

  /// Clicking one modifier and nothing else binds that modifier bare, which is
  /// how the default fn and right ⌥ triggers are shaped.
  @Test func aLoneModifierBindsItself() {
    let binding = ShortcutAssignment.binding(forClicked: [61], layout: layout)
    #expect(binding?.keyCode == 61)
    #expect(binding?.modifierFlags == 0)
    #expect(binding?.isModifierKey == true)
  }

  /// fn cannot be a required modifier — a binding stores only command, option,
  /// control and shift — so clicking fn first makes it the key.
  @Test func fnIsAlwaysTheKeyNeverAModifier() {
    let binding = ShortcutAssignment.binding(forClicked: [63, 58], layout: layout)
    #expect(binding?.keyCode == 63)
    #expect(binding?.modifiers.contains(.maskSecondaryFn) == false)
    #expect(binding?.modifiers == .maskAlternate)
  }

  @Test func clickingNothingBindsNothing() {
    #expect(ShortcutAssignment.binding(forClicked: [], layout: layout) == nil)
  }
}
