import AppKit

@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let toggleDictation: () -> Void
    private let toggleReadAloud: () -> Void
    private let openSettings: () -> Void
    private let dictationItem: NSMenuItem
    private let readAloudItem: NSMenuItem
    private var blinkTimer: Timer?
    private var blinkDimmed = false

    init(
        toggleDictation: @escaping () -> Void,
        toggleReadAloud: @escaping () -> Void,
        openSettings: @escaping () -> Void
    ) {
        self.toggleDictation = toggleDictation
        self.toggleReadAloud = toggleReadAloud
        self.openSettings = openSettings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        dictationItem = NSMenuItem(title: "Start Dictation", action: nil, keyEquivalent: "")
        readAloudItem = NSMenuItem(title: "Read Selected Text", action: nil, keyEquivalent: "")
        super.init()

        statusItem.button?.image = NSImage(named: "MenuBarIcon")
        statusItem.button?.image?.accessibilityDescription = "Talkify"

        let menu = NSMenu()

        dictationItem.action = #selector(toggleDictationItem)
        dictationItem.target = self
        menu.addItem(dictationItem)

        readAloudItem.action = #selector(toggleReadAloudItem)
        readAloudItem.target = self
        menu.addItem(readAloudItem)
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

    /// Mirrors the session state on the shell: the ghost pulses between
    /// full and dimmed tint while recording, and the menu item flips.
    func setRecording(_ isRecording: Bool) {
        dictationItem.title = isRecording ? "Stop Dictation" : "Start Dictation"
        if isRecording {
            startBlinking()
        } else {
            stopBlinking()
        }
    }

    /// Shows the recorded bindings as menu hints; the event tap does the
    /// real work, these only display. Bare modifier keys cannot render as
    /// key equivalents, so those ride a trailing badge instead.
    func setKeyBindings(trigger: KeyBinding, readAloud: KeyBinding) {
        dictationItem.badge = NSMenuItemBadge(string: trigger.label)
        if readAloud.keyEquivalent.isEmpty {
            readAloudItem.keyEquivalent = ""
            readAloudItem.badge = NSMenuItemBadge(string: readAloud.label)
        } else {
            readAloudItem.badge = nil
            readAloudItem.keyEquivalent = readAloud.keyEquivalent
            readAloudItem.keyEquivalentModifierMask = readAloud.cocoaModifiers
        }
    }

    private func startBlinking() {
        guard blinkTimer == nil else { return }
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.blinkDimmed.toggle()
                self.statusItem.button?.contentTintColor =
                    self.blinkDimmed ? .tertiaryLabelColor : .labelColor
            }
        }
    }

    private func stopBlinking() {
        blinkTimer?.invalidate()
        blinkTimer = nil
        blinkDimmed = false
        statusItem.button?.contentTintColor = nil
    }

    /// Mirrors Read Aloud playback on the menu item.
    func setSpeaking(_ isSpeaking: Bool) {
        readAloudItem.title = isSpeaking ? "Stop Reading" : "Read Selected Text"
    }

    @objc private func toggleDictationItem() {
        toggleDictation()
    }

    @objc private func toggleReadAloudItem() {
        toggleReadAloud()
    }

    @objc private func openSettingsItem() {
        openSettings()
    }
}
