import ApplicationServices
import Foundation
import OSLog

final class DictationTriggerMonitor: @unchecked Sendable {
    enum Event: Sendable {
        case triggerPressed
        case triggerReleased
        case cancelPressed
    }

    private static let functionKeyCode: Int64 = 63

    private let handler: @Sendable (Event) -> Void
    private let logger = Logger(subsystem: "com.tgomareli.Talkify", category: "TriggerDiagnosis")
    private let stateLock = NSLock()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var functionKeyIsDown = false
    private var captureEscape = false

    init(handler: @escaping @Sendable (Event) -> Void) {
        self.handler = handler
    }

    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else { return true }

        logger.notice("[DEBUG-fn8b] start requested")

        let mask = eventMask(for: [
            .flagsChanged,
            .keyDown,
            .tapDisabledByTimeout,
            .tapDisabledByUserInput,
        ])

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }

            let monitor = Unmanaged<DictationTriggerMonitor>
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
            logger.error("[DEBUG-fn8b] event tap creation failed")
            return false
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0) else {
            logger.error("[DEBUG-fn8b] run-loop source creation failed")
            CFMachPortInvalidate(eventTap)
            return false
        }

        self.eventTap = eventTap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        logger.notice("[DEBUG-fn8b] event tap installed")
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
            functionKeyIsDown = false
            captureEscape = false
        }
    }

    func setEscapeCaptureEnabled(_ enabled: Bool) {
        stateLock.withLock {
            captureEscape = enabled
        }
    }

    private func process(
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            logger.error("[DEBUG-fn8b] event tap disabled type=\(type.rawValue)")
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        if type == .flagsChanged {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            logger.notice(
                "[DEBUG-fn8b] flags keyCode=\(keyCode) value=\(event.flags.rawValue)"
            )
            guard keyCode == Self.functionKeyCode else {
                return Unmanaged.passUnretained(event)
            }

            let isDown = event.flags.contains(.maskSecondaryFn)
            var output: Event?

            stateLock.withLock {
                guard isDown != functionKeyIsDown else { return }
                functionKeyIsDown = isDown
                output = isDown ? .triggerPressed : .triggerReleased
            }

            if let output {
                logger.notice("[DEBUG-fn8b] trigger emitted")
                handler(output)
            }
            return nil
        }

        if type == .keyDown,
           event.getIntegerValueField(.keyboardEventKeycode) == 53 {
            let shouldCapture = stateLock.withLock { captureEscape }
            guard shouldCapture else { return Unmanaged.passUnretained(event) }

            handler(.cancelPressed)
            return nil
        }

        return Unmanaged.passUnretained(event)
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
