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
  @Test func fnUsesItsSharedFlag() throws {
    let fn = KeyBinding.fnTrigger
    #expect(KeyBinding.deviceMasks(forKeyCode: try #require(fn.keyCode)) == nil)
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


  /// A third modifier means some other shortcut is being typed.
  @Test func anExtraModifierDoesNotMatch() {
    #expect(!GlobalKeyEventMonitor.isTriggerHeld(
      fnOption, flags: [.maskSecondaryFn, .maskAlternate, .maskCommand]
    ))
    #expect(!GlobalKeyEventMonitor.isTriggerHeld(fn, flags: [.maskSecondaryFn, .maskCommand]))
  }

  /// A plain letter with a modifier — ⇧P. The bound key is not a modifier, so
  /// the keyDown path matches it, and it must require the shift it was
  /// recorded with rather than firing on a lone p.
  @Test func aLetterWithAModifierIsAValidTrigger() {
    let shiftP = KeyBinding(
      keyCode: 35,
      modifierFlags: CGEventFlags.maskShift.rawValue,
      isModifierKey: false,
      label: "⇧ P",
      keyEquivalent: "p"
    )
    #expect(GlobalKeyEventMonitor.flagsMatch(.maskShift, mask: shiftP.modifiers))
    #expect(!GlobalKeyEventMonitor.flagsMatch([], mask: shiftP.modifiers))
    #expect(!GlobalKeyEventMonitor.flagsMatch([.maskShift, .maskCommand], mask: shiftP.modifiers))

    // Both shift keys light up, since either one satisfies the binding.
    #expect(KeyboardMap.highlighted(for: shiftP) == [35, 56, 60])
  }

}

/// Regressions found reviewing the combo work. Each of these was assignable in
/// Settings and then did nothing.
struct ComboTriggerRegressionTests {
  /// ⇧ + ⌥, where the bound key is itself one of the four combining modifiers.
  /// Its own bit is in the flags, so an exact match against the required
  /// modifiers alone can never be satisfied and the binding is dead.
  @Test func aModifierBoundWithAnotherModifierStillFires() {
    let shiftOption = KeyBinding(
      keyCode: 58,
      modifierFlags: CGEventFlags.maskShift.rawValue,
      isModifierKey: true,
      label: "⇧ ⌥",
      keyEquivalent: ""
    )
    let bothDown = CGEventFlags(
      rawValue: CGEventFlags([.maskShift, .maskAlternate]).rawValue | 0x20
    )
    #expect(GlobalKeyEventMonitor.isTriggerHeld(shiftOption, flags: bothDown))

    let onlyOption = CGEventFlags(rawValue: CGEventFlags.maskAlternate.rawValue | 0x20)
    #expect(!GlobalKeyEventMonitor.isTriggerHeld(shiftOption, flags: onlyOption))
  }

  /// The recorder must keep fn as the bound key whichever order the two were
  /// pressed in. Pressing fn first and adding ⌥ used to overwrite the chord
  /// and bind a bare ⌥, which then fires on every Option press.
  @Test func theChordKeepsTheKeyThatOutranksAModifier() {
    #expect(KeyBinding.chordKey(existing: 63, pressed: 58) == 63)
    #expect(KeyBinding.chordKey(existing: 58, pressed: 63) == 63)
    #expect(KeyBinding.chordKey(existing: nil, pressed: 58) == 58)
    // Two combining modifiers: the newest wins, so ⇧ then ⌥ binds ⌥ + ⇧.
    #expect(KeyBinding.chordKey(existing: 56, pressed: 58) == 58)
  }
}

@Suite("Mouse-button triggers")
struct MouseButtonTriggerTests {
  private final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [GlobalKeyEventMonitor.Event] = []

    func append(_ event: GlobalKeyEventMonitor.Event) {
      lock.lock()
      stored.append(event)
      lock.unlock()
    }

    var events: [GlobalKeyEventMonitor.Event] {
      lock.lock()
      defer { lock.unlock() }
      return stored
    }
  }

  private func mouseEvent(
    _ type: CGEventType,
    buttonNumber: Int64,
    flags: CGEventFlags = []
  ) throws -> CGEvent {
    let button = try #require(CGMouseButton(rawValue: UInt32(buttonNumber)))
    let event = try #require(CGEvent(
      mouseEventSource: nil,
      mouseType: type,
      mouseCursorPosition: .zero,
      mouseButton: button
    ))
    event.flags = flags
    event.setIntegerValueField(.mouseEventButtonNumber, value: buttonNumber)
    return event
  }

  @Test func middleClickPressesAndReleasesThePrimaryTrigger() throws {
    let log = EventLog()
    let monitor = GlobalKeyEventMonitor(handler: log.append)
    let middleClick = try #require(KeyBinding.mouseButton(number: 2))
    monitor.setBindings(trigger: middleClick, secondaryTrigger: nil, readAloud: .optionEscape)

    let down = try mouseEvent(.otherMouseDown, buttonNumber: 2)
    let up = try mouseEvent(.otherMouseUp, buttonNumber: 2)

    #expect(monitor.process(type: .otherMouseDown, event: down) == nil)
    #expect(monitor.process(type: .otherMouseUp, event: up) == nil)
    #expect(log.events == [.triggerPressed(.primary), .triggerReleased(.primary)])
  }

  /// The point of binding a combination: the bare button is left alone. A
  /// trigger that ate every middle click would take away the button the user
  /// was trying to keep.
  @Test func aBareClickPassesThroughWhenTheTriggerNeedsAModifier() throws {
    let log = EventLog()
    let monitor = GlobalKeyEventMonitor(handler: log.append)
    let optionMiddle = try #require(KeyBinding.mouseButton(number: 2, modifiers: [.option]))
    monitor.setBindings(trigger: optionMiddle, secondaryTrigger: nil, readAloud: .optionEscape)

    let bareDown = try mouseEvent(.otherMouseDown, buttonNumber: 2)
    let bareDrag = try mouseEvent(.otherMouseDragged, buttonNumber: 2)
    let bareUp = try mouseEvent(.otherMouseUp, buttonNumber: 2)
    #expect(monitor.process(type: .otherMouseDown, event: bareDown) != nil)
    #expect(monitor.process(type: .otherMouseDragged, event: bareDrag) != nil)
    #expect(monitor.process(type: .otherMouseUp, event: bareUp) != nil)
    #expect(log.events.isEmpty)

    let optionDown = try mouseEvent(
      .otherMouseDown,
      buttonNumber: 2,
      flags: .maskAlternate
    )
    #expect(monitor.process(type: .otherMouseDown, event: optionDown) == nil)
    #expect(log.events == [.triggerPressed(.primary)])
  }

  /// A modifier pressed after the button changes nothing: that click already
  /// belongs to whatever is under the pointer.
  @Test func aModifierAfterAnUnmatchedClickStartsNothing() throws {
    let log = EventLog()
    let monitor = GlobalKeyEventMonitor(handler: log.append)
    let optionMiddle = try #require(KeyBinding.mouseButton(number: 2, modifiers: [.option]))
    monitor.setBindings(trigger: optionMiddle, secondaryTrigger: nil, readAloud: .optionEscape)

    let middleDown = try mouseEvent(.otherMouseDown, buttonNumber: 2)
    #expect(monitor.process(type: .otherMouseDown, event: middleDown) != nil)

    let optionDown = try #require(CGEvent(
      keyboardEventSource: nil,
      virtualKey: 58,
      keyDown: true
    ))
    optionDown.flags = .maskAlternate
    #expect(monitor.process(type: .flagsChanged, event: optionDown) != nil)
    #expect(log.events.isEmpty)
  }

  @Test func secondaryCanReuseThePrimaryMouseButtonWithDifferentModifiers() throws {
    let log = EventLog()
    let monitor = GlobalKeyEventMonitor(handler: log.append)
    let middleClick = try #require(KeyBinding.mouseButton(number: 2))
    let optionMiddle = try #require(KeyBinding.mouseButton(number: 2, modifiers: [.option]))
    monitor.setBindings(
      trigger: middleClick,
      secondaryTrigger: optionMiddle,
      readAloud: .optionEscape
    )

    let optionDown = try mouseEvent(
      .otherMouseDown,
      buttonNumber: 2,
      flags: .maskAlternate
    )
    #expect(monitor.process(type: .otherMouseDown, event: optionDown) == nil)
    #expect(log.events == [.triggerPressed(.secondary)])
  }

  @Test func secondaryCanReuseThePrimaryKeyboardKeyWithDifferentModifiers() throws {
    let log = EventLog()
    let monitor = GlobalKeyEventMonitor(handler: log.append)
    let plainP = KeyBinding(
      keyCode: 35,
      modifierFlags: 0,
      isModifierKey: false,
      label: "P",
      keyEquivalent: "p"
    )
    let shiftP = KeyBinding(
      keyCode: 35,
      modifierFlags: CGEventFlags.maskShift.rawValue,
      isModifierKey: false,
      label: "⇧ P",
      keyEquivalent: "p"
    )
    monitor.setBindings(trigger: plainP, secondaryTrigger: shiftP, readAloud: .optionEscape)

    let event = try #require(CGEvent(
      keyboardEventSource: nil,
      virtualKey: 35,
      keyDown: true
    ))
    event.flags = .maskShift
    #expect(monitor.process(type: .keyDown, event: event) == nil)
    #expect(log.events == [.triggerPressed(.secondary)])
  }

  @Test func anUnboundMouseButtonPassesThrough() throws {
    let log = EventLog()
    let monitor = GlobalKeyEventMonitor(handler: log.append)
    let middleClick = try #require(KeyBinding.mouseButton(number: 2))
    monitor.setBindings(trigger: middleClick, secondaryTrigger: nil, readAloud: .optionEscape)

    let down = try mouseEvent(.otherMouseDown, buttonNumber: 3)
    let up = try mouseEvent(.otherMouseUp, buttonNumber: 3)
    #expect(monitor.process(type: .otherMouseDown, event: down) != nil)
    #expect(monitor.process(type: .otherMouseUp, event: up) != nil)
    #expect(log.events.isEmpty)
  }

  @Test func aSecondBoundMouseButtonIsReservedWhileAnotherIsCaptured() throws {
    let log = EventLog()
    let monitor = GlobalKeyEventMonitor(handler: log.append)
    let middleClick = try #require(KeyBinding.mouseButton(number: 2))
    let mouseFour = try #require(KeyBinding.mouseButton(number: 3))
    monitor.setBindings(
      trigger: middleClick,
      secondaryTrigger: mouseFour,
      readAloud: .optionEscape
    )

    #expect(monitor.process(
      type: .otherMouseDown,
      event: try mouseEvent(.otherMouseDown, buttonNumber: 2)
    ) == nil)
    #expect(monitor.process(
      type: .otherMouseDown,
      event: try mouseEvent(.otherMouseDown, buttonNumber: 3)
    ) == nil)
    #expect(monitor.process(
      type: .otherMouseUp,
      event: try mouseEvent(.otherMouseUp, buttonNumber: 3)
    ) == nil)
    #expect(log.events == [.triggerPressed(.primary)])

    #expect(monitor.process(
      type: .otherMouseUp,
      event: try mouseEvent(.otherMouseUp, buttonNumber: 2)
    ) == nil)
    #expect(log.events == [.triggerPressed(.primary), .triggerReleased(.primary)])
  }

  /// One session at a time. The other language's button is swallowed while fn
  /// holds the session — so its release can be swallowed too — but it starts
  /// nothing, and it does not start late once fn is let go either.
  @Test func aMousePressedDuringAnotherSessionStaysInert() throws {
    let log = EventLog()
    let monitor = GlobalKeyEventMonitor(handler: log.append)
    let middleClick = try #require(KeyBinding.mouseButton(number: 2))
    monitor.setBindings(
      trigger: .fnTrigger,
      secondaryTrigger: middleClick,
      readAloud: .optionEscape
    )

    let fnDown = try #require(CGEvent(
      keyboardEventSource: nil,
      virtualKey: 63,
      keyDown: true
    ))
    fnDown.flags = .maskSecondaryFn
    #expect(monitor.process(type: .flagsChanged, event: fnDown) == nil)

    #expect(monitor.process(
      type: .otherMouseDown,
      event: try mouseEvent(.otherMouseDown, buttonNumber: 2)
    ) == nil)
    #expect(log.events == [.triggerPressed(.primary)])

    let fnUp = try #require(CGEvent(
      keyboardEventSource: nil,
      virtualKey: 63,
      keyDown: false
    ))
    fnUp.flags = []
    #expect(monitor.process(type: .flagsChanged, event: fnUp) == nil)

    #expect(monitor.process(
      type: .otherMouseUp,
      event: try mouseEvent(.otherMouseUp, buttonNumber: 2)
    ) == nil)
    #expect(log.events == [.triggerPressed(.primary), .triggerReleased(.primary)])
  }

  @Test func aCapturedMouseDragIsSwallowed() throws {
    let log = EventLog()
    let monitor = GlobalKeyEventMonitor(handler: log.append)
    let middleClick = try #require(KeyBinding.mouseButton(number: 2))
    monitor.setBindings(trigger: middleClick, secondaryTrigger: nil, readAloud: .optionEscape)

    #expect(monitor.process(
      type: .otherMouseDown,
      event: try mouseEvent(.otherMouseDown, buttonNumber: 2)
    ) == nil)
    #expect(monitor.process(
      type: .otherMouseDragged,
      event: try mouseEvent(.otherMouseDragged, buttonNumber: 2)
    ) == nil)
    #expect(monitor.process(
      type: .otherMouseUp,
      event: try mouseEvent(.otherMouseUp, buttonNumber: 2)
    ) == nil)
  }

  @Test func sharedKeyboardKeyReleasesTheSlotThatActuallyStarted() throws {
    let log = EventLog()
    let monitor = GlobalKeyEventMonitor(handler: log.append)
    let plainP = KeyBinding(
      keyCode: 35,
      modifierFlags: 0,
      isModifierKey: false,
      label: "P",
      keyEquivalent: "p"
    )
    let shiftP = KeyBinding(
      keyCode: 35,
      modifierFlags: CGEventFlags.maskShift.rawValue,
      isModifierKey: false,
      label: "⇧ P",
      keyEquivalent: "p"
    )
    monitor.setBindings(trigger: plainP, secondaryTrigger: shiftP, readAloud: .optionEscape)

    let down = try #require(CGEvent(
      keyboardEventSource: nil,
      virtualKey: 35,
      keyDown: true
    ))
    down.flags = .maskShift
    #expect(monitor.process(type: .keyDown, event: down) == nil)

    let up = try #require(CGEvent(
      keyboardEventSource: nil,
      virtualKey: 35,
      keyDown: false
    ))
    up.flags = []
    #expect(monitor.process(type: .keyUp, event: up) == nil)
    #expect(log.events == [.triggerPressed(.secondary), .triggerReleased(.secondary)])
  }

  @Test func releasingAModifierEndsButStillCapturesTheMouseUp() throws {
    let log = EventLog()
    let monitor = GlobalKeyEventMonitor(handler: log.append)
    let optionMiddle = try #require(KeyBinding.mouseButton(number: 2, modifiers: [.option]))
    monitor.setBindings(trigger: optionMiddle, secondaryTrigger: nil, readAloud: .optionEscape)

    let down = try mouseEvent(.otherMouseDown, buttonNumber: 2, flags: .maskAlternate)
    #expect(monitor.process(type: .otherMouseDown, event: down) == nil)

    let modifierRelease = try #require(CGEvent(
      keyboardEventSource: nil,
      virtualKey: 58,
      keyDown: false
    ))
    modifierRelease.flags = []
    #expect(monitor.process(type: .flagsChanged, event: modifierRelease) != nil)

    let up = try mouseEvent(.otherMouseUp, buttonNumber: 2)
    #expect(monitor.process(type: .otherMouseUp, event: up) == nil)
    #expect(log.events == [.triggerPressed(.primary), .triggerReleased(.primary)])
  }

  @Test func leftRightAndButtonsAboveTheSystemLimitAreNotBindable() {
    #expect(KeyBinding.mouseButton(number: 0) == nil)
    #expect(KeyBinding.mouseButton(number: 1) == nil)
    #expect(KeyBinding.mouseButton(number: 32) == nil)
    #expect(KeyBinding.mouseButton(number: 2)?.label == "Middle Click")
    #expect(KeyBinding.mouseButton(number: 31)?.label == "Mouse 32")
  }
}
