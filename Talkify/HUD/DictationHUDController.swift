import AppKit
import SwiftUI

/// The Direct Dictation HUD surface: a NotchIsland-style shape that descends
/// from the top center of the selected display. Non-activating and
/// click-through; the host window is sized once per display and only its
/// origin moves. The voice-reactive visual and long-draft variants stay open
/// (CONTEXT.md flagged ambiguities).
@MainActor
final class DictationHUDController {
    private static let messageDuration = Duration.seconds(2)
    private static let latchedText = "Listening (latched)"

    private enum Mode {
        case hidden
        case session
        case message
    }

    private let panel: DictationHUDPanel
    private let hostingView: NSHostingView<DictationHUDShellView>
    private let content = DictationHUDContent()
    private var mode = Mode.hidden
    private var messageDismissTask: Task<Void, Never>?

    init() {
        let placeholder = HUDScreenSnapshot(
            id: 0,
            frame: .zero,
            safeAreaTop: 0,
            auxiliaryTopLeftArea: nil,
            auxiliaryTopRightArea: nil
        )
        hostingView = NSHostingView(
            rootView: DictationHUDShellView(screen: placeholder, content: content)
        )
        // The window size is this controller's decision, not the content's;
        // without this the hosting view imposes the shell's intrinsic size on
        // the window and collapses the fixed frame.
        hostingView.sizingOptions = []
        panel = DictationHUDPanel(
            contentRect: CGRect(origin: .zero, size: CGSize(width: 1, height: 1)),
            contentView: hostingView
        )
    }

    func showMessage(_ text: String) {
        showMessage(text, on: nil)
    }

    func showMessage(_ text: String, on displayID: CGDirectDisplayID?) {
        guard let screen = selectScreen(targetDisplayID: displayID) else { return }
        mode = .message
        present(text, on: screen)
        scheduleMessageDismiss()
    }

    func showListening(on displayID: CGDirectDisplayID?, isLatched: Bool) {
        guard let screen = selectScreen(targetDisplayID: displayID) else { return }
        cancelMessageDismiss()
        mode = .session
        present(isLatched ? Self.latchedText : "Listening…", on: screen)
    }

    func showLatched() {
        guard case .session = mode else { return }
        content.text = Self.latchedText
    }

    func showLiveText(_ text: String) {
        guard case .session = mode, !text.isEmpty else { return }
        content.text = text
    }

    func showFinalizing() {
        guard case .session = mode else { return }
        content.text = "Finalizing…"
    }

    func hide() {
        cancelMessageDismiss()
        mode = .hidden
        panel.orderOut(nil)
    }

    private func selectScreen(targetDisplayID: CGDirectDisplayID?) -> HUDScreenSnapshot? {
        let screens = NSScreen.screens.compactMap { screen -> HUDScreenSnapshot? in
            guard let id = screen.cgDirectDisplayID else { return nil }
            return HUDScreenSnapshot(
                id: id,
                frame: screen.frame,
                safeAreaTop: screen.safeAreaInsets.top,
                auxiliaryTopLeftArea: screen.auxiliaryTopLeftArea,
                auxiliaryTopRightArea: screen.auxiliaryTopRightArea
            )
        }
        return HUDPlacement.selectDisplay(
            from: screens,
            targetDisplayID: targetDisplayID,
            pointerLocation: NSEvent.mouseLocation
        )
    }

    private func present(_ text: String, on screen: HUDScreenSnapshot) {
        content.text = text
        hostingView.rootView = DictationHUDShellView(screen: screen, content: content)
        panel.setFrame(HUDNotchGeometry.windowFrame(for: screen), display: true)
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
