import AppKit

@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let toggleDictation: () -> Void
    private let openSettings: () -> Void
    private let dictationItem: NSMenuItem

    init(
        toggleDictation: @escaping () -> Void,
        openSettings: @escaping () -> Void
    ) {
        self.toggleDictation = toggleDictation
        self.openSettings = openSettings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        dictationItem = NSMenuItem(title: "Start Dictation", action: nil, keyEquivalent: "")
        super.init()

        statusItem.button?.image = NSImage(
            systemSymbolName: "microphone",
            accessibilityDescription: "Talkify"
        )

        let menu = NSMenu()

        dictationItem.action = #selector(toggleDictationItem)
        dictationItem.target = self
        menu.addItem(dictationItem)
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettingsItem),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem(
            title: "Quit Talkify",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        statusItem.menu = menu
    }

    /// Mirrors the session state on the shell: filled red microphone and a
    /// "Stop Dictation" item while recording.
    func setRecording(_ isRecording: Bool) {
        statusItem.button?.image = NSImage(
            systemSymbolName: isRecording ? "microphone.fill" : "microphone",
            accessibilityDescription: "Talkify"
        )
        statusItem.button?.contentTintColor = isRecording ? .systemRed : nil
        dictationItem.title = isRecording ? "Stop Dictation" : "Start Dictation"
    }

    @objc private func toggleDictationItem() {
        toggleDictation()
    }

    @objc private func openSettingsItem() {
        openSettings()
    }
}
