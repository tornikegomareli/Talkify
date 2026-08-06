import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settings: AppSettings?
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
        let settings = AppSettings()
        self.settings = settings
        let hudController = DictationHUDController(settings: settings)
        let dictationController = DirectDictationController(hudController: hudController)
        self.hudController = hudController
        self.dictationController = dictationController

        let statusItemController = StatusItemController {
            dictationController.toggleFromMenu()
        }
        self.statusItemController = statusItemController

        dictationController.onRecordingStateChange = { [weak statusItemController] isRecording in
            statusItemController?.setRecording(isRecording)
        }

        // Requests permissions and prepares the selected Speech Model
        // shortly after launch (CONTEXT.md).
        dictationController.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        dictationController?.stop()
    }
}
