import ApplicationServices
import Foundation

final class GlobalKeyEventMonitor: @unchecked Sendable {
  /// Which dictation trigger fired. Each slot carries its own language, so
  /// the controller needs to know which key started the session.
  enum TriggerSlot: Sendable, Equatable {
    case primary
    case secondary
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
  /// Every bound mouse button currently down. All remain swallowed through
  /// drag and up, even when another trigger owns the session.
  private var capturedMouseButtons: Set<Int64> = []
  /// Captured buttons pressed while no session was active. Only these may
  /// start later when a modifier completes their combination; a button pressed
  /// while another trigger was active stays inert until it comes up.
  private var pendingMouseButtons: Set<Int64> = []
  private var captureEscape = false
  /// True while a Settings key recorder is armed: every event passes
  /// through untouched so the rebind keystroke cannot start a session.
  private var suspended = false
  // Bindings, mutable from the main actor via setBindings; read on the
  // tap thread under the lock. Defaults match AppSettings' defaults.
  private var triggerBinding = KeyBinding.fnTrigger
  /// The second language's trigger; nil when no second language is chosen.
  private var secondaryTriggerBinding: KeyBinding?
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
      pendingMouseButtons.removeAll()
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
    readAloud: KeyBinding
  ) {
    stateLock.withLock {
      triggerBinding = trigger
      // A second trigger identical to the first would make the slot
      // ambiguous, so the primary always wins and the second is dropped. Only
      // the inputs matter here: the same binding recorded and clicked carries
      // a different label, and comparing whole values would miss the clash.
      let isDuplicate = secondaryTrigger?.hasSameInputAndModifiers(as: trigger) ?? false
      secondaryTriggerBinding = isDuplicate ? nil : secondaryTrigger
      readAloudBinding = readAloud
      heldSlot = nil
      capturedMouseButtons.removeAll()
      pendingMouseButtons.removeAll()
    }
  }

  /// Pauses all handling while a Settings key recorder is armed.
  func setEventHandlingSuspended(_ isSuspended: Bool) {
    stateLock.withLock {
      suspended = isSuspended
      heldSlot = nil
      capturedMouseButtons.removeAll()
      pendingMouseButtons.removeAll()
    }
  }

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

    if type == .otherMouseDown {
      let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
      var output: Event?
      var wasCaptured = false
      stateLock.withLock {
        guard hasMouseTrigger(forButtonNumber: buttonNumber) else { return }
        wasCaptured = true
        guard capturedMouseButtons.insert(buttonNumber).inserted else { return }
        guard heldSlot == nil else { return }
        pendingMouseButtons.insert(buttonNumber)
        guard let (slot, _) = satisfiedMouseTrigger(
          forButtonNumber: buttonNumber,
          flags: event.flags
        ) else { return }
        heldSlot = slot
        pendingMouseButtons.remove(buttonNumber)
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
        pendingMouseButtons.remove(buttonNumber)
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
        // is released. Its later mouse-up remains captured separately.
        if let held = heldSlot,
           let binding = binding(for: held),
           binding.isMouseButton {
          guard !Self.flagsMatch(event.flags, mask: binding.modifiers) else { return }
          heldSlot = nil
          if let buttonNumber = binding.mouseButtonNumber,
             capturedMouseButtons.contains(buttonNumber) {
            pendingMouseButtons.insert(buttonNumber)
          }
          output = .triggerReleased(held)
          return
        }

        // A mouse button may land before its required modifiers. Its down was
        // already captured, so whichever later flags change completes the
        // exact binding starts the session without leaking the click.
        if heldSlot == nil,
           let (slot, binding) = satisfiedPendingMouseTrigger(flags: event.flags) {
          heldSlot = slot
          if let buttonNumber = binding.mouseButtonNumber {
            pendingMouseButtons.remove(buttonNumber)
          }
          output = .triggerPressed(slot)
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
      if !readAloud.isMouseButton,
       keyCode == readAloud.keyCode,
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
           !binding.isMouseButton,
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

  /// Resolves a keycode to a trigger slot. Both helpers must be called with
  /// `stateLock` held; the primary is checked first so it wins any overlap.
  private func modifierTrigger(forKeyCode keyCode: Int64) -> (TriggerSlot, KeyBinding)? {
    if !triggerBinding.isMouseButton,
     triggerBinding.isModifierKey,
     keyCode == triggerBinding.keyCode {
      return (.primary, triggerBinding)
    }
    if let secondary = secondaryTriggerBinding,
     !secondary.isMouseButton,
     secondary.isModifierKey, keyCode == secondary.keyCode {
      return (.secondary, secondary)
    }
    return nil
  }

  /// The modifier trigger these flags currently satisfy, primary first so it
  /// wins any overlap. Called with `stateLock` held.
  private func satisfiedModifierTrigger(flags: CGEventFlags) -> (TriggerSlot, KeyBinding)? {
    if !triggerBinding.isMouseButton,
     triggerBinding.isModifierKey,
     Self.isTriggerHeld(triggerBinding, flags: flags) {
      return (.primary, triggerBinding)
    }
    if let secondary = secondaryTriggerBinding,
     !secondary.isMouseButton,
     secondary.isModifierKey, Self.isTriggerHeld(secondary, flags: flags) {
      return (.secondary, secondary)
    }
    return nil
  }

  /// The binding behind a currently held slot, when it is a modifier trigger.
  /// A plain key has its own keyUp to end on, so it is not re-evaluated here.
  private func heldModifierBinding(_ slot: TriggerSlot) -> KeyBinding? {
    let binding = binding(for: slot)
    guard let binding, binding.isModifierKey else { return nil }
    return binding
  }

  private func binding(for slot: TriggerSlot) -> KeyBinding? {
    slot == .primary ? triggerBinding : secondaryTriggerBinding
  }

  private func plainKeyTrigger(
    forKeyCode keyCode: Int64,
    flags: CGEventFlags
  ) -> (TriggerSlot, KeyBinding)? {
    if !triggerBinding.isMouseButton,
     !triggerBinding.isModifierKey,
     keyCode == triggerBinding.keyCode,
     Self.flagsMatch(flags, mask: triggerBinding.modifiers) {
      return (.primary, triggerBinding)
    }
    if let secondary = secondaryTriggerBinding,
     !secondary.isMouseButton,
     !secondary.isModifierKey,
     keyCode == secondary.keyCode,
     Self.flagsMatch(flags, mask: secondary.modifiers) {
      return (.secondary, secondary)
    }
    return nil
  }

  private func hasMouseTrigger(forButtonNumber buttonNumber: Int64) -> Bool {
    triggerBinding.mouseButtonNumber == buttonNumber
      || secondaryTriggerBinding?.mouseButtonNumber == buttonNumber
  }

  private func satisfiedMouseTrigger(
    forButtonNumber buttonNumber: Int64,
    flags: CGEventFlags
  ) -> (TriggerSlot, KeyBinding)? {
    if triggerBinding.mouseButtonNumber == buttonNumber,
     Self.flagsMatch(flags, mask: triggerBinding.modifiers) {
      return (.primary, triggerBinding)
    }
    if let secondary = secondaryTriggerBinding,
     secondary.mouseButtonNumber == buttonNumber,
     Self.flagsMatch(flags, mask: secondary.modifiers) {
      return (.secondary, secondary)
    }
    return nil
  }

  private func satisfiedPendingMouseTrigger(
    flags: CGEventFlags
  ) -> (TriggerSlot, KeyBinding)? {
    if let buttonNumber = triggerBinding.mouseButtonNumber,
     pendingMouseButtons.contains(buttonNumber),
     Self.flagsMatch(flags, mask: triggerBinding.modifiers) {
      return (.primary, triggerBinding)
    }
    if let secondary = secondaryTriggerBinding,
     let buttonNumber = secondary.mouseButtonNumber,
     pendingMouseButtons.contains(buttonNumber),
     Self.flagsMatch(flags, mask: secondary.modifiers) {
      return (.secondary, secondary)
    }
    return nil
  }

  /// Whether the bound modifier key itself is down.
  ///
  /// The shared flag cannot answer this for a side-specific key: with left ⌥
  /// held, releasing right ⌥ leaves `.maskAlternate` set. The per-key device
  /// bits can, so they decide whenever this keyboard reports them. If the
  /// shared flag says down while both device bits are clear, nothing is
  /// reporting them and the shared flag is all there is.
  static func isModifierKeyDown(_ binding: KeyBinding, flags: CGEventFlags) -> Bool {
    guard !binding.isMouseButton else { return false }
    let sharedDown = flags.contains(binding.modifierKeyMask)
    guard let masks = KeyBinding.deviceMasks(forKeyCode: binding.keyCode) else {
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
    guard !binding.isMouseButton else { return false }
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
