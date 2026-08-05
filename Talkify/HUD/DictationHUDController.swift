import AppKit

/// The Direct Dictation HUD surface. Milestone 1 scope: behavior, not looks —
/// a non-activating, click-through panel at the top center of the selected
/// display. Notch geometry, animation, and the voice-reactive visual come later.
@MainActor
final class DictationHUDController {
    private static let panelSize = CGSize(width: 420, height: 56)
    private static let messageDuration = Duration.seconds(2)
    private static let latchedText = "Listening (latched)"

    private enum Mode {
        case hidden
        case session
        case message
    }

    private let panel: NSPanel
    private let label: NSTextField
    private var mode = Mode.hidden
    private var messageDismissTask: Task<Void, Never>?

    init() {
        panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        let background = NSView()
        background.wantsLayer = true
        background.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.85).cgColor
        background.layer?.cornerRadius = 12

        label = NSTextField(labelWithString: "")
        label.textColor = .white
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.alignment = .center
        // Tail-only truncation: long drafts show the newest words (CONTEXT.md
        // flags long-draft behavior as undecided; this is the current variant).
        label.lineBreakMode = .byTruncatingHead
        label.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -16),
            label.centerYAnchor.constraint(equalTo: background.centerYAnchor),
        ])

        panel.contentView = background
    }

    func showMessage(_ text: String) {
        showMessage(text, on: nil)
    }

    func showMessage(_ text: String, on displayID: CGDirectDisplayID?) {
        guard let display = selectDisplay(targetDisplayID: displayID) else { return }
        mode = .message
        present(text, on: display)
        scheduleMessageDismiss()
    }

    func showListening(on displayID: CGDirectDisplayID?, isLatched: Bool) {
        guard let display = selectDisplay(targetDisplayID: displayID) else { return }
        cancelMessageDismiss()
        mode = .session
        present(isLatched ? Self.latchedText : "Listening…", on: display)
    }

    func showLatched() {
        guard case .session = mode else { return }
        label.stringValue = Self.latchedText
    }

    func showLiveText(_ text: String) {
        guard case .session = mode, !text.isEmpty else { return }
        label.stringValue = text
    }

    func showFinalizing() {
        guard case .session = mode else { return }
        label.stringValue = "Finalizing…"
    }

    func hide() {
        cancelMessageDismiss()
        mode = .hidden
        panel.orderOut(nil)
    }

    private func selectDisplay(targetDisplayID: CGDirectDisplayID?) -> HUDPlacement.Display? {
        let displays = NSScreen.screens.compactMap { screen -> HUDPlacement.Display? in
            guard let id = screen.cgDirectDisplayID else { return nil }
            return HUDPlacement.Display(id: id, frame: screen.frame)
        }
        return HUDPlacement.selectDisplay(
            from: displays,
            targetDisplayID: targetDisplayID,
            pointerLocation: NSEvent.mouseLocation
        )
    }

    private func present(_ text: String, on display: HUDPlacement.Display) {
        label.stringValue = text
        panel.setFrame(
            HUDPlacement.panelFrame(on: display, panelSize: Self.panelSize),
            display: true
        )
        panel.orderFrontRegardless()
    }

    private func scheduleMessageDismiss() {
        messageDismissTask?.cancel()
        messageDismissTask = Task { [weak self] in
            try? await Task.sleep(for: Self.messageDuration)
            guard !Task.isCancelled, let self, case .message = mode else { return }
            hide()
        }
    }

    private func cancelMessageDismiss() {
        messageDismissTask?.cancel()
        messageDismissTask = nil
    }
}
