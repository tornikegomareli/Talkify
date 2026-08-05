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
        let demoItem = NSMenuItem(
            title: "Debug: HUD Demo",
            action: #selector(runHUDDemo),
            keyEquivalent: ""
        )
        demoItem.target = self
        menu.addItem(demoItem)
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(
            title: "Quit Talkify",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        statusItem.menu = menu
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
