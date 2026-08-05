import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?
    private var hudController: DictationHUDController?

    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let hudController = DictationHUDController()
        self.hudController = hudController
        statusItemController = StatusItemController(hudController: hudController)

        // Temporary M1.2 demo hook for headless verification; M1.3 removes it
        // together with the debug menu item.
        if ProcessInfo.processInfo.arguments.contains("--hud-demo") {
            statusItemController?.runHUDDemo()
        }
    }
}
