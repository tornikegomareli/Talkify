import AppKit
import ApplicationServices
import Testing
@testable import Talkify

/// Down/up detection for a modifier-key trigger.
///
/// `CGEventFlags` collapses left and right into one bit, so with left ⌥ held,
/// releasing right ⌥ still reports `.maskAlternate`. A trigger bound to right ⌥
/// would never see its release and the session would stay open. The per-key
/// device bits are what make the two distinguishable.
struct ModifierTriggerTests {
  private let rightOption = KeyBinding.rightOptionTrigger
  private let leftOption = KeyBinding(
    keyCode: 58, modifierFlags: 0, isModifierKey: true,
    label: "⌥", keyEquivalent: ""
  )

  /// From IOKit's IOLLEvent.h: left ⌥ is 0x20, right ⌥ is 0x40.
  private func flags(shared: Bool, device: UInt64) -> CGEventFlags {
    CGEventFlags(rawValue: (shared ? CGEventFlags.maskAlternate.rawValue : 0) | device)
  }

  @Test func rightOptionIsDownOnlyWhenItsOwnBitIsSet() {
    #expect(GlobalKeyEventMonitor.isModifierKeyDown(
      rightOption, flags: flags(shared: true, device: 0x40)
    ))
    #expect(!GlobalKeyEventMonitor.isModifierKeyDown(
      rightOption, flags: flags(shared: false, device: 0)
    ))
  }

  /// The regression: left ⌥ held, right ⌥ released. The shared flag is still
  /// set, and reading it alone would keep the session open forever.
  @Test func releasingRightOptionWhileLeftIsHeldReadsAsUp() {
    let bothDown = flags(shared: true, device: 0x20 | 0x40)
    #expect(GlobalKeyEventMonitor.isModifierKeyDown(rightOption, flags: bothDown))

    let onlyLeftDown = flags(shared: true, device: 0x20)
    #expect(!GlobalKeyEventMonitor.isModifierKeyDown(rightOption, flags: onlyLeftDown))
    #expect(GlobalKeyEventMonitor.isModifierKeyDown(leftOption, flags: onlyLeftDown))
  }

  /// A keyboard that reports no device bits at all still has to work: the
  /// shared flag is then the only signal there is.
  @Test func fallsBackToTheSharedFlagWithoutDeviceBits() {
    #expect(GlobalKeyEventMonitor.isModifierKeyDown(
      rightOption, flags: flags(shared: true, device: 0)
    ))
    #expect(!GlobalKeyEventMonitor.isModifierKeyDown(
      leftOption, flags: flags(shared: false, device: 0)
    ))
  }

  /// fn has no twin, so it keeps using its own flag and no device bits.
  @Test func fnUsesItsSharedFlag() {
    let fn = KeyBinding.fnTrigger
    #expect(KeyBinding.deviceMasks(forKeyCode: fn.keyCode) == nil)
    #expect(GlobalKeyEventMonitor.isModifierKeyDown(
      fn, flags: CGEventFlags.maskSecondaryFn
    ))
    #expect(!GlobalKeyEventMonitor.isModifierKeyDown(fn, flags: []))
  }

  /// Every side-specific modifier is covered, not only Option, since any of
  /// them can be recorded as a trigger.
  @Test func everySidedModifierHasDistinctBits() {
    let pairs = [(55, 54), (58, 61), (59, 62), (56, 60)]
    for (left, right) in pairs {
      let l = try! #require(KeyBinding.deviceMasks(forKeyCode: Int64(left)))
      let r = try! #require(KeyBinding.deviceMasks(forKeyCode: Int64(right)))
      #expect(l.own != r.own, "keycodes \(left)/\(right) share a device bit")
      #expect(l.pair == r.pair, "keycodes \(left)/\(right) disagree on their pair")
      #expect(l.pair == l.own | r.own)
    }
  }

  @Test func commandModifiedKeyIsNotABareTriggerPress() {
    #expect(!GlobalKeyEventMonitor.flagsMatch(.maskCommand, mask: []))
    #expect(GlobalKeyEventMonitor.flagsMatch([], mask: []))
  }
}

/// The whole trigger, not just its key: the bound key down plus exactly the
/// modifiers it was recorded with. This is what lets fn + ⌥ be a trigger while
/// fn on its own keeps scrolling pages (issue #40).
struct ComboTriggerTests {
  private let fn = KeyBinding.fnTrigger
  private let fnOption = KeyBinding(
    keyCode: 63,
    modifierFlags: CGEventFlags.maskAlternate.rawValue,
    isModifierKey: true,
    label: "⌥ fn",
    keyEquivalent: ""
  )

  @Test func aBareModifierTriggerStillFiresOnItsOwn() {
    #expect(GlobalKeyEventMonitor.isTriggerHeld(fn, flags: .maskSecondaryFn))
    #expect(!GlobalKeyEventMonitor.isTriggerHeld(fn, flags: []))
  }

  /// The point of the feature.
  @Test func aComboTriggerNeedsBothKeys() {
    #expect(!GlobalKeyEventMonitor.isTriggerHeld(fnOption, flags: .maskSecondaryFn))
    #expect(!GlobalKeyEventMonitor.isTriggerHeld(fnOption, flags: .maskAlternate))
    #expect(GlobalKeyEventMonitor.isTriggerHeld(
      fnOption, flags: [.maskSecondaryFn, .maskAlternate]
    ))
  }

  /// Letting go of the modifier breaks it even though the bound key is still
  /// down. The released keycode alone could never tell us that, which is why
  /// the monitor re-checks the whole combination on every flags change.
  @Test func releasingEitherKeyBreaksTheCombo() {
    #expect(!GlobalKeyEventMonitor.isTriggerHeld(fnOption, flags: .maskSecondaryFn))
    #expect(!GlobalKeyEventMonitor.isTriggerHeld(fnOption, flags: .maskAlternate))
  }

  /// A third modifier means some other shortcut is being typed.
  @Test func anExtraModifierDoesNotMatch() {
    #expect(!GlobalKeyEventMonitor.isTriggerHeld(
      fnOption, flags: [.maskSecondaryFn, .maskAlternate, .maskCommand]
    ))
    #expect(!GlobalKeyEventMonitor.isTriggerHeld(fn, flags: [.maskSecondaryFn, .maskCommand]))
  }

  /// The recorder subtracts the bound key's own contribution, so a trigger
  /// never ends up requiring itself as one of its modifiers.
  @Test func aModifierKeyDoesNotRequireItself() {
    #expect(KeyBinding.cocoaModifier(forKeyCode: 58) == .option)
    #expect(KeyBinding.cocoaModifier(forKeyCode: 61) == .option)
    #expect(KeyBinding.cocoaModifier(forKeyCode: 63) == [])
  }
}
