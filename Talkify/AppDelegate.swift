import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?
    private var hudController: DictationHUDController?
    private var dictationController: DirectDictationController?

    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let hudController = DictationHUDController()
        let dictationController = DirectDictationController(hudController: hudController)
        self.hudController = hudController
        self.dictationController = dictationController

        let statusItemController = StatusItemController(hudController: hudController) {
            dictationController.toggleFromMenu()
        }
        self.statusItemController = statusItemController

        dictationController.onRecordingStateChange = { [weak statusItemController] isRecording in
            statusItemController?.setRecording(isRecording)
        }

        // Requests permissions and prepares the selected Speech Model
        // shortly after launch (CONTEXT.md).
        dictationController.start()

        // Debug hook for headless HUD verification; goes away with the debug
        // menu items once the Settings picker exists.
        if ProcessInfo.processInfo.arguments.contains("--hud-demo") {
            statusItemController.runHUDDemo()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        dictationController?.stop()
    }
}
