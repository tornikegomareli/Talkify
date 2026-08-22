import ApplicationServices
import Foundation

final class GlobalKeyEventMonitor: @unchecked Sendable {
  /// Which dictation trigger fired. Each slot carries its own language, so
  /// the controller needs to know which key started the session.
  enum TriggerSlot: Sendable, Equatable {
    case primary
    case secondary
    /// Dictates in the primary language and inserts a translation. A slot
    /// rather than a separate binding because it needs the same one-at-a-time
    /// arbitration every trigger needs: heldSlot is what makes a session
    /// exclusive, a held combination end when it breaks, and a swallowed
    /// mouse button stay swallowed.
    case translate

    /// The preference this slot's key comes from, so a session can capture the
    /// key it started with.
    var bindingRole: BindingRole {
      switch self {
      case .primary: .dictation
      case .secondary: .secondLanguage
      case .translate: .translate
      }
    }
  }

  enum Event: Sendable, Equatable {
    case triggerPressed(TriggerSlot)
    case triggerReleased(TriggerSlot)
    case cancelPressed
    /// Option+Escape — the Read Aloud toggle, matching the shortcut
    /// macOS Spoken Content uses for "speak selection".
    case readAloudPressed
  }

  private let handler: @Sendable (Event) -> Void
  private let stateLock = NSLock()

  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  /// Which slot's key is currently held, nil when none. One at a time: the
  /// other language's trigger is inert until this one is released, so a session
  /// can never be half German and half English.
  private var heldSlot: TriggerSlot?
  /// Mouse buttons whose press this tap swallowed. They stay swallowed
  /// through drag and up: letting the release through after eating the press
  /// leaves the app under the pointer believing the button is still down.
  private var capturedMouseButtons: Set<Int64> = []
  private var captureEscape = false
  /// True while a Settings key recorder is armed: every event passes
  /// through untouched so the rebind keystroke cannot start a session.
  private var suspended = false
  // Bindings, mutable from the main actor via setBindings; read on the
  // tap thread under the lock. Defaults match AppSettings' defaults.
  /// Every bound slot, in the order that settles an overlap: primary first,
  /// then secondary, then translate. Ordered rather than keyed, because the
  /// precedence is a rule and a dictionary has none. One table rather than a
  /// field per slot, so a new slot cannot be forgotten in a resolver and
  /// silently answer as another one.
  private var slotBindings: [(slot: TriggerSlot, binding: KeyBinding)] = [
    (.primary, .fnTrigger),
  ]
  private var readAloudBinding = KeyBinding.optionEscape

  init(handler: @escaping @Sendable (Event) -> Void) {
    self.handler = handler
  }

  @discardableResult
  func start() -> Bool {
    guard eventTap == nil else { return true }

    let mask = eventMask(for: [
      .flagsChanged,
      .keyDown,
      .keyUp,
      .otherMouseDown,
      .otherMouseDragged,
      .otherMouseUp,
      .tapDisabledByTimeout,
      .tapDisabledByUserInput,
    ])

    let callback: CGEventTapCallBack = { _, type, event, userInfo in
      guard let userInfo else { return Unmanaged.passUnretained(event) }

      let monitor = Unmanaged<GlobalKeyEventMonitor>
        .fromOpaque(userInfo)
        .takeUnretainedValue()

      return monitor.process(type: type, event: event)
    }

    guard let eventTap = CGEvent.tapCreate(
      tap: .cgSessionEventTap,
      place: .headInsertEventTap,
      options: .defaultTap,
      eventsOfInterest: mask,
      callback: callback,
      userInfo: Unmanaged.passUnretained(self).toOpaque()
    ) else {
      return false
    }

    guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0) else {
      CFMachPortInvalidate(eventTap)
      return false
    }

    self.eventTap = eventTap
    runLoopSource = source
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: eventTap, enable: true)
    return true
  }

  func stop() {
    guard let eventTap else { return }

    CGEvent.tapEnable(tap: eventTap, enable: false)
    CFMachPortInvalidate(eventTap)

    if let runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
    }

    self.eventTap = nil
    runLoopSource = nil

    stateLock.withLock {
      heldSlot = nil
      capturedMouseButtons.removeAll()
      captureEscape = false
    }
  }

  func setEscapeCaptureEnabled(_ enabled: Bool) {
    stateLock.withLock {
      captureEscape = enabled
    }
  }

  /// Applies the recorded Settings bindings. Safe while the tap runs; an
  /// input held through a rebind simply never delivers its release.
  /// `secondaryTrigger` is nil when no second language is chosen.
  func setBindings(
    trigger: KeyBinding,
    secondaryTrigger: KeyBinding?,
    readAloud: KeyBinding,
    translateTrigger: KeyBinding? = nil
  ) {
    stateLock.withLock {
      // Two triggers on the same input would make the slot ambiguous, so an
      // earlier slot always wins and the later one is dropped. Only the inputs
      // matter: the same binding recorded and clicked carries a different
      // label, and comparing whole values would miss the clash.
      var accepted: [(slot: TriggerSlot, binding: KeyBinding)] = []
      for candidate in [
        (TriggerSlot.primary, Optional(trigger)),
        (.secondary, secondaryTrigger),
        (.translate, translateTrigger),
      ] {
        guard let binding = candidate.1 else { continue }
        let clashes = accepted.contains { $0.binding.hasSameInputAndModifiers(as: binding) }
        guard !clashes else { continue }
        accepted.append((candidate.0, binding))
      }
      // A rebind lands mid-gesture whenever something rebinds itself: choosing
      // a translation target reapplies the bindings, and a finished model
      // install writes that setting on its own. Dropping the held slot there
      // means the release never arrives, so the session records until Escape
      // and the words are lost. A slot whose binding did not change stays held.
      let heldBinding = slotBindings.first { $0.slot == heldSlot }?.binding
      let isStillHeld = heldBinding.map { binding in
        accepted.contains {
          $0.slot == heldSlot && $0.binding.hasSameInputAndModifiers(as: binding)
        }
      } ?? false

      slotBindings = accepted
      readAloudBinding = readAloud
      if !isStillHeld {
        heldSlot = nil
      }
      // capturedMouseButtons is deliberately left alone. Its whole job is to
      // remember a press this tap ate so the matching release is eaten too,
      // and letting that release through leaves the application under the
      // pointer believing the button is still down (CONTEXT.md). Only
      // otherMouseUp may drain it. Ending a session reapplies the bindings,
      // and a mouse gesture that ended by releasing its modifier first is
      // still holding its button at exactly that moment.
    }
  }

  /// Pauses all handling while a Settings key recorder is armed.
  func setEventHandlingSuspended(_ isSuspended: Bool) {
    stateLock.withLock {
      suspended = isSuspended
      heldSlot = nil
      capturedMouseButtons.removeAll()
    }
  }

  /// The tap callback's body. Internal rather than private so the gesture
  /// rules can be driven with synthetic events instead of a live tap; nothing
  /// outside the tests calls it.
  func process(
    type: CGEventType,
    event: CGEvent
  ) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      if let eventTap {
        CGEvent.tapEnable(tap: eventTap, enable: true)
      }
      return Unmanaged.passUnretained(event)
    }

    let isSuspended = stateLock.withLock { suspended }
    if isSuspended {
      return Unmanaged.passUnretained(event)
    }

    // A bound button is swallowed only while its exact combination is
    // pressed, exactly as a bound key is: someone who binds ⌥ + Middle did so
    // to keep plain middle click, and taking that away globally would be the
    // opposite of what they asked for.
    if type == .otherMouseDown {
      let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
      var output: Event?
      var wasCaptured = false
      stateLock.withLock {
        guard let (slot, _) = satisfiedMouseTrigger(
          forButtonNumber: buttonNumber,
          flags: event.flags
        ) else { return }
        wasCaptured = true
        guard capturedMouseButtons.insert(buttonNumber).inserted else { return }
        // Another trigger owns the session: the press is still swallowed, so
        // its release can be too, but it starts nothing.
        guard heldSlot == nil else { return }
        heldSlot = slot
        output = .triggerPressed(slot)
      }
      if let output { handler(output) }
      return wasCaptured ? nil : Unmanaged.passUnretained(event)
    }

    if type == .otherMouseDragged {
      let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
      let wasCaptured = stateLock.withLock {
        capturedMouseButtons.contains(buttonNumber)
      }
      return wasCaptured ? nil : Unmanaged.passUnretained(event)
    }

    if type == .otherMouseUp {
      let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
      var output: Event?
      let wasCaptured = stateLock.withLock {
        guard capturedMouseButtons.remove(buttonNumber) != nil else { return false }
        if let held = heldSlot,
           binding(for: held)?.mouseButtonNumber == buttonNumber {
          heldSlot = nil
          output = .triggerReleased(held)
        }
        return true
      }
      if let output { handler(output) }
      return wasCaptured ? nil : Unmanaged.passUnretained(event)
    }

    if type == .flagsChanged {
      let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
      var output: Event?
      // Only the trigger's own key is swallowed. Eating a plain ⌥ release
      // would leave every other app believing ⌥ is still held.
      var matchedKeyCode: Int64?

      stateLock.withLock {
        // A mouse trigger with required modifiers ends as soon as one of them
        // is released, the same way a key combination does. The button's own
        // release stays captured, so nothing leaks when it finally comes up.
        if let held = heldSlot,
           let binding = binding(for: held),
           binding.isMouseButton {
          guard !Self.flagsMatch(event.flags, mask: binding.modifiers) else { return }
          heldSlot = nil
          output = .triggerReleased(held)
          return
        }

        // A held modifier trigger ends the moment its combination breaks,
        // whoever broke it: with fn + ⌥ the released key is often ⌥, whose
        // keycode is not the one the trigger is bound to.
        if let held = heldSlot, let binding = heldModifierBinding(held) {
          guard !Self.isTriggerHeld(binding, flags: event.flags) else { return }
          heldSlot = nil
          matchedKeyCode = binding.keyCode
          output = .triggerReleased(held)
          return
        }

        // Whichever key completed the combination starts it, not only the
        // bound one: holding fn and adding ⌥ arrives as an ⌥ event, and gating
        // on the bound keycode would mean the session never starts.
        //
        // Another language's key already held wins, rather than starting a
        // second session on top of the first.
        guard heldSlot == nil, let (slot, binding) = satisfiedModifierTrigger(flags: event.flags)
        else { return }
        heldSlot = slot
        matchedKeyCode = binding.keyCode
        output = .triggerPressed(slot)
      }

      if let output {
        handler(output)
        return matchedKeyCode == keyCode ? nil : Unmanaged.passUnretained(event)
      }
      return Unmanaged.passUnretained(event)
    }

    if type == .keyDown {
      let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
      let (readAloud, shouldCapture, plainTrigger) = stateLock.withLock {
        (
          readAloudBinding,
          captureEscape,
          plainKeyTrigger(forKeyCode: keyCode, flags: event.flags)
        )
      }

      // A non-modifier trigger key: press starts the hold gesture.
      // Autorepeat is the key being held, not pressed again.
      if let (slot, _) = plainTrigger {
        guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else {
          return nil
        }
        var output: Event?
        stateLock.withLock {
          guard heldSlot == nil else { return }
          heldSlot = slot
          output = .triggerPressed(slot)
        }
        if let output { handler(output) }
        return nil
      }

      // The Read Aloud shortcut is always swallowed, so the system
      // Spoken Content shortcut never double-fires on the same combo.
      if keyCode == readAloud.keyCode,
       Self.flagsMatch(event.flags, mask: readAloud.modifiers) {
        handler(.readAloudPressed)
        return nil
      }

      // Plain Escape stays the dictation cancel, captured mid-session.
      if keyCode == 53, shouldCapture {
        handler(.cancelPressed)
        return nil
      }

      return Unmanaged.passUnretained(event)
    }

    if type == .keyUp {
      let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
      var output: Event?
      stateLock.withLock {
        guard let held = heldSlot,
           let binding = binding(for: held),
           !binding.isModifierKey,
           binding.keyCode == keyCode
        else { return }
        heldSlot = nil
        output = .triggerReleased(held)
      }
      if let output {
        handler(output)
        return nil
      }
      return Unmanaged.passUnretained(event)
    }

    return Unmanaged.passUnretained(event)
  }

  /// The modifier trigger these flags currently satisfy, primary first so it
  /// wins any overlap. Called with `stateLock` held.
  private func satisfiedModifierTrigger(flags: CGEventFlags) -> (TriggerSlot, KeyBinding)? {
    slotBindings.first {
      $0.binding.isModifierKey && Self.isTriggerHeld($0.binding, flags: flags)
    }
  }

  /// The binding behind a currently held slot, when it is a modifier trigger.
  /// A plain key has its own keyUp to end on, so it is not re-evaluated here.
  private func heldModifierBinding(_ slot: TriggerSlot) -> KeyBinding? {
    let binding = binding(for: slot)
    guard let binding, binding.isModifierKey else { return nil }
    return binding
  }

  private func binding(for slot: TriggerSlot) -> KeyBinding? {
    slotBindings.first { $0.slot == slot }?.binding
  }

  private func plainKeyTrigger(
    forKeyCode keyCode: Int64,
    flags: CGEventFlags
  ) -> (TriggerSlot, KeyBinding)? {
    slotBindings.first {
      !$0.binding.isModifierKey
        && keyCode == $0.binding.keyCode
        && Self.flagsMatch(flags, mask: $0.binding.modifiers)
    }
  }

  private func satisfiedMouseTrigger(
    forButtonNumber buttonNumber: Int64,
    flags: CGEventFlags
  ) -> (TriggerSlot, KeyBinding)? {
    slotBindings.first {
      $0.binding.mouseButtonNumber == buttonNumber
        && Self.flagsMatch(flags, mask: $0.binding.modifiers)
    }
  }

  /// Whether the bound modifier key itself is down.
  ///
  /// The shared flag cannot answer this for a side-specific key: with left ⌥
  /// held, releasing right ⌥ leaves `.maskAlternate` set. The per-key device
  /// bits can, so they decide whenever this keyboard reports them. If the
  /// shared flag says down while both device bits are clear, nothing is
  /// reporting them and the shared flag is all there is.
  static func isModifierKeyDown(_ binding: KeyBinding, flags: CGEventFlags) -> Bool {
    guard let keyCode = binding.keyCode else { return false }
    let sharedDown = flags.contains(binding.modifierKeyMask)
    guard let masks = KeyBinding.deviceMasks(forKeyCode: keyCode) else {
      return sharedDown
    }
    if sharedDown, flags.rawValue & masks.pair == 0 {
      return true
    }
    return flags.rawValue & masks.own != 0
  }

  /// Whether the whole trigger is down: the bound key, plus exactly the
  /// modifiers it was recorded with and no others.
  ///
  /// The bound key's own bit is subtracted first. ⇧ bound with ⌥ required puts
  /// both bits in the flags, and comparing that against ⌥ alone could never
  /// match — the binding would be assignable and permanently dead.
  static func isTriggerHeld(_ binding: KeyBinding, flags: CGEventFlags) -> Bool {
    guard isModifierKeyDown(binding, flags: flags) else { return false }
    return flagsMatch(flags.subtracting(binding.modifierKeyMask), mask: binding.modifiers)
  }

  /// Exact-modifier match: ⌥⎋ means Option and only Option; a bare key
  /// (F13) means no modifiers at all.
  static func flagsMatch(_ flags: CGEventFlags, mask: CGEventFlags) -> Bool {
    let relevant: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
    return flags.intersection(relevant) == mask.intersection(relevant)
  }

  private func eventMask(for types: [CGEventType]) -> CGEventMask {
    types.reduce(0) { mask, type in
      mask | (CGEventMask(1) << type.rawValue)
    }
  }
}

private extension NSLock {
  func withLock<Result>(_ body: () throws -> Result) rethrows -> Result {
    lock()
    defer { unlock() }
    return try body()
  }
}
