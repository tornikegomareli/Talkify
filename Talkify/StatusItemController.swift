import AppKit

@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let hudController: DictationHUDController
    private var demoTask: Task<Void, Never>?

    init(hudController: DictationHUDController) {
        self.hudController = hudController
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        statusItem.button?.image = NSImage(
            systemSymbolName: "microphone",
            accessibilityDescription: "Talkify"
        )

        let menu = NSMenu()

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
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(
            title: "Quit Talkify",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        statusItem.menu = menu
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
        demoTask = Task { [hudController] in
            hudController.showListening(on: nil, isLatched: false)
            try? await Task.sleep(for: .seconds(1))
            hudController.showLiveText("Draft text arrives")
            try? await Task.sleep(for: .seconds(1))
            hudController.showLiveText("Draft text arrives and keeps updating while you speak")
            try? await Task.sleep(for: .seconds(1))
            hudController.showLatched()
            try? await Task.sleep(for: .seconds(1))
            hudController.showFinalizing()
            try? await Task.sleep(for: .seconds(1))
            hudController.hide()
            hudController.showMessage("Demo finished")
        }
    }
}
