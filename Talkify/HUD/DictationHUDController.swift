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
    /// How long the retract animation needs before the panel can order out.
    /// A perceptual duration rather than the spring's settling time, per
    /// WWDC23 "Animate with springs": don't wait for settling.
    private static let dismissDuration = Duration.milliseconds(350)
    private static let latchedText = "Listening (latched)"

    private enum Mode {
        case hidden
        case session
        case message
    }

    private let panel: DictationHUDPanel
    private let hostingView: NSHostingView<DictationHUDShellView>
    private let content = DictationHUDContent()
    private let sounds = DictationHUDSounds()
    private var mode = Mode.hidden
    private var messageDismissTask: Task<Void, Never>?
    private var orderOutTask: Task<Void, Never>?

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
        if let stored = UserDefaults.standard.string(forKey: Self.revealStyleKey),
           let style = HUDRevealStyle(rawValue: stored) {
            content.revealStyle = style
        }
        if let stored = UserDefaults.standard.string(forKey: Self.longDraftStyleKey),
           let style = HUDLongDraftStyle(rawValue: stored) {
            content.longDraftStyle = style
        }
    }

    private static let revealStyleKey = "hudRevealStyle"
    private static let longDraftStyleKey = "hudLongDraftStyle"

    /// Debug-only hook for auditioning reveal styles from the menu; the
    /// future Settings UI replaces it. Persists like the sound set.
    func useRevealStyle(_ style: HUDRevealStyle) {
        content.revealStyle = style
        UserDefaults.standard.set(style.rawValue, forKey: Self.revealStyleKey)
    }

    /// Debug-only hook for auditioning long-draft variants; same pattern.
    func useLongDraftStyle(_ style: HUDLongDraftStyle) {
        content.longDraftStyle = style
        UserDefaults.standard.set(style.rawValue, forKey: Self.longDraftStyleKey)
    }

    /// Debug-only hook for auditioning the candidate sound sets from the
    /// menu; the future Settings UI replaces it.
    func useSounds(_ set: DictationSoundSet) {
        sounds.set = set
    }

    /// Played when finalized text lands in the target. M1.3 wires this to
    /// text insertion; until then only the debug demo calls it.
    func playPasteSound() {
        sounds.playPaste()
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
        sounds.playBegin()
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
        if case .session = mode {
            sounds.playEnd()
        }
        mode = .hidden
        content.isRevealed = false

        // Keep the panel front while the retract plays, then order out.
        orderOutTask?.cancel()
        orderOutTask = Task { [weak self] in
            try? await Task.sleep(for: Self.dismissDuration)
            guard !Task.isCancelled, let self, case .hidden = mode else { return }
            panel.orderOut(nil)
        }
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
        orderOutTask?.cancel()
        content.text = text
        hostingView.rootView = DictationHUDShellView(screen: screen, content: content)
        panel.setFrame(HUDNotchGeometry.windowFrame(for: screen), display: true)
        panel.orderFrontRegardless()

        guard !content.isRevealed else { return }
        // The shell needs one committed frame in its parked position or the
        // reveal renders already-descended and the animation never plays.
        // Force that frame synchronously, then flip on the next runloop tick.
        panel.displayIfNeeded()
        Task { @MainActor [content] in
            content.isRevealed = true
        }
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
