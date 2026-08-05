import AppKit

@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let hudController: DictationHUDController
    private let toggleDictation: () -> Void
    private let dictationItem: NSMenuItem
    private var demoTask: Task<Void, Never>?
    private var demoLevelTask: Task<Void, Never>?

    init(hudController: DictationHUDController, toggleDictation: @escaping () -> Void) {
        self.hudController = hudController
        self.toggleDictation = toggleDictation
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

        // Temporary M1.2 demo of the HUD surface; ticket M1.3 removes it.
        // One item per candidate sound set so the pick can be judged by ear.
        for set in DictationSoundSet.allCases {
            let demoItem = NSMenuItem(
                title: "Debug: HUD Demo (\(set.rawValue))",
                action: #selector(runHUDDemoItem(_:)),
                keyEquivalent: ""
            )
            demoItem.target = self
            demoItem.representedObject = set.rawValue
            menu.addItem(demoItem)
        }

        // Same idea for the reveal animation: pick a style, see the demo.
        let animationItem = NSMenuItem(title: "Debug: HUD Animation", action: nil, keyEquivalent: "")
        let animationMenu = NSMenu()
        for style in HUDRevealStyle.allCases {
            let styleItem = NSMenuItem(
                title: style.rawValue,
                action: #selector(runHUDDemoWithStyle(_:)),
                keyEquivalent: ""
            )
            styleItem.target = self
            styleItem.representedObject = style.rawValue
            animationMenu.addItem(styleItem)
        }
        animationItem.submenu = animationMenu
        menu.addItem(animationItem)

        // And for the flagged long-draft variants (CONTEXT.md): pick, see the demo.
        let draftItem = NSMenuItem(title: "Debug: HUD Long Drafts", action: nil, keyEquivalent: "")
        let draftMenu = NSMenu()
        for style in HUDLongDraftStyle.allCases {
            let styleItem = NSMenuItem(
                title: style.rawValue,
                action: #selector(runHUDDemoWithDraftStyle(_:)),
                keyEquivalent: ""
            )
            styleItem.target = self
            styleItem.representedObject = style.rawValue
            draftMenu.addItem(styleItem)
        }
        draftItem.submenu = draftMenu
        menu.addItem(draftItem)

        // And for the flagged voice-reactive visual (CONTEXT.md).
        let visualItem = NSMenuItem(title: "Debug: HUD Voice Visual", action: nil, keyEquivalent: "")
        let visualMenu = NSMenu()
        for style in HUDVoiceVisualStyle.allCases {
            let styleItem = NSMenuItem(
                title: style.rawValue,
                action: #selector(runHUDDemoWithVisual(_:)),
                keyEquivalent: ""
            )
            styleItem.target = self
            styleItem.representedObject = style.rawValue
            visualMenu.addItem(styleItem)
        }
        visualItem.submenu = visualMenu
        menu.addItem(visualItem)
        menu.addItem(.separator())

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

    @objc private func runHUDDemoWithVisual(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String,
           let style = HUDVoiceVisualStyle(rawValue: raw) {
            hudController.useVoiceVisual(style)
        }
        runHUDDemo()
    }

    @objc private func runHUDDemoWithDraftStyle(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String,
           let style = HUDLongDraftStyle(rawValue: raw) {
            hudController.useLongDraftStyle(style)
        }
        runHUDDemo()
    }

    @objc private func runHUDDemoWithStyle(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String,
           let style = HUDRevealStyle(rawValue: raw) {
            hudController.useRevealStyle(style)
        }
        runHUDDemo()
    }

    @objc private func runHUDDemoItem(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String,
           let set = DictationSoundSet(rawValue: raw) {
            hudController.useSounds(set)
        }
        runHUDDemo()
    }

    @objc func runHUDDemo() {
        demoTask?.cancel()
        demoLevelTask?.cancel()
        demoTask = Task { [hudController] in
            hudController.showListening(on: nil, isLatched: false)
            startDemoLevels()
            try? await Task.sleep(for: .seconds(1))
            hudController.showLiveText("Draft text arrives")
            try? await Task.sleep(for: .seconds(1))
            hudController.showLiveText("Draft text arrives and keeps updating while you speak")
            try? await Task.sleep(for: .seconds(1))
            hudController.showLiveText(
                "Draft text arrives and keeps updating while you speak, and when a draft "
                + "runs long enough to outgrow a single line the selected long-draft "
                + "variant decides whether it truncates, wraps and grows, or shrinks to fit"
            )
            try? await Task.sleep(for: .seconds(2))
            hudController.showLatched()
            try? await Task.sleep(for: .seconds(1))
            demoLevelTask?.cancel()
            hudController.showFinalizing()
            try? await Task.sleep(for: .seconds(1))
            hudController.hide()
            try? await Task.sleep(for: .milliseconds(500))
            hudController.playPasteSound()
            hudController.showMessage("Demo finished")
        }
    }

    /// Synthesized speech-like levels so the voice visuals can be auditioned
    /// without dictating: syllable bursts over a quiet noise floor.
    private func startDemoLevels() {
        demoLevelTask?.cancel()
        demoLevelTask = Task { [hudController] in
            var t = 0.0
            while !Task.isCancelled {
                let burst = max(0, sin(t * 5.6))
                let level = 0.05 + burst * (0.3 + 0.35 * Double.random(in: 0...1))
                hudController.showAudioLevel(Float(min(1, level)))
                t += 0.022
                try? await Task.sleep(for: .milliseconds(22))
            }
        }
    }
}
