import AppKit
import SwiftUI

/// Hosts the SwiftUI Settings form in a plain titled window. The app is
/// menu-bar-only (LSUIElement), so showing the window must activate the app
/// explicitly or it never comes forward.
@MainActor
final class SettingsWindowController: NSWindowController {
    convenience init(settings: AppSettings, sounds: DictationHUDSounds) {
        let hosting = NSHostingController(
            rootView: SettingsView(settings: settings, sounds: sounds)
        )
        let window = NSWindow(contentViewController: hosting)
        window.title = "Talkify Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        self.init(window: window)
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }
}
