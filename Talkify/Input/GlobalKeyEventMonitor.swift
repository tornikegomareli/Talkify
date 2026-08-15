import ApplicationServices
import Foundation

final class GlobalKeyEventMonitor: @unchecked Sendable {
  /// Which dictation trigger fired. Each slot carries its own language, so
  /// the controller needs to know which key started the session.
  enum TriggerSlot: Sendable {
    case primary
    case secondary
  }

  enum Event: Sendable {
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
  /// other language's key is inert until this one is released, so a session
  /// can never be half German and half English.
  private var heldSlot: TriggerSlot?
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
      captureEscape = false
    }
  }

  func setEscapeCaptureEnabled(_ enabled: Bool) {
    stateLock.withLock {
      captureEscape = enabled
    }
  }

  /// Applies the recorded Settings bindings. Safe while the tap runs; a
  /// key held through a rebind simply never delivers its release.
  /// `secondaryTrigger` is nil when no second language is chosen.
  func setBindings(
    trigger: KeyBinding,
    secondaryTrigger: KeyBinding?,
    readAloud: KeyBinding
  ) {
    stateLock.withLock {
      triggerBinding = trigger
      // A second trigger identical to the first would make the slot
      // ambiguous, so the primary always wins and the second is dropped.
      secondaryTriggerBinding = secondaryTrigger == trigger ? nil : secondaryTrigger
      readAloudBinding = readAloud
      heldSlot = nil
    }
  }

  /// Pauses all handling while a Settings key recorder is armed.
  func setEventHandlingSuspended(_ isSuspended: Bool) {
    stateLock.withLock {
      suspended = isSuspended
      heldSlot = nil
    }
  }

  private func process(
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

    if type == .flagsChanged {
      let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
      var output: Event?

      stateLock.withLock {
        guard let (slot, binding) = modifierTrigger(forKeyCode: keyCode) else { return }
        let isDown = Self.isModifierKeyDown(binding, flags: event.flags)

        if isDown {
          // Another language's key is already held; ignore this one rather
          // than starting a second session on top of the first.
          guard heldSlot == nil else { return }
          heldSlot = slot
          output = .triggerPressed(slot)
        } else {
          guard heldSlot == slot else { return }
          heldSlot = nil
          output = .triggerReleased(slot)
        }
      }

      if let output {
        handler(output)
        return nil
      }
      return Unmanaged.passUnretained(event)
    }

    if type == .keyDown {
      let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
      let (readAloud, shouldCapture, plainTrigger) = stateLock.withLock {
        (readAloudBinding, captureEscape, plainKeyTrigger(forKeyCode: keyCode))
      }

      // A non-modifier trigger key: press starts the hold gesture.
      // Autorepeat is the key being held, not pressed again.
      if let (slot, _) = plainTrigger,
         Self.isPlainTriggerPress(flags: event.flags) {
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
        guard let (slot, _) = plainKeyTrigger(forKeyCode: keyCode),
           heldSlot == slot else { return }
        heldSlot = nil
        output = .triggerReleased(slot)
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
    if triggerBinding.isModifierKey, keyCode == triggerBinding.keyCode {
      return (.primary, triggerBinding)
    }
    if let secondary = secondaryTriggerBinding,
     secondary.isModifierKey, keyCode == secondary.keyCode {
      return (.secondary, secondary)
    }
    return nil
  }

  private func plainKeyTrigger(forKeyCode keyCode: Int64) -> (TriggerSlot, KeyBinding)? {
    if !triggerBinding.isModifierKey, keyCode == triggerBinding.keyCode {
      return (.primary, triggerBinding)
    }
    if let secondary = secondaryTriggerBinding,
     !secondary.isModifierKey, keyCode == secondary.keyCode {
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
    let sharedDown = flags.contains(binding.modifierKeyMask)
    guard let masks = KeyBinding.deviceMasks(forKeyCode: binding.keyCode) else {
      return sharedDown
    }
    if sharedDown, flags.rawValue & masks.pair == 0 {
      return true
    }
    return flags.rawValue & masks.own != 0
  }

  static func isPlainTriggerPress(flags: CGEventFlags) -> Bool {
    flagsMatch(flags, mask: [])
  }

  /// Exact-modifier match: ⌥⎋ means Option and only Option; a bare key
  /// (F13) means no modifiers at all.
  private static func flagsMatch(_ flags: CGEventFlags, mask: CGEventFlags) -> Bool {
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
