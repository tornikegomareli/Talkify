import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settings: AppSettings?
    private var statusItemController: StatusItemController?
    private var hudController: DictationHUDController?
    private var dictationController: DirectDictationController?
    private var settingsWindowController: SettingsWindowController?
    private let settingsRuntimeState = SettingsRuntimeState()

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
        let dictationController = DirectDictationController(
            settings: settings,
            hudController: hudController
        )
        self.hudController = hudController
        self.dictationController = dictationController

        let statusItemController = StatusItemController(
            toggleDictation: { dictationController.toggleFromMenu() },
            openSettings: { [weak self] in self?.showSettings() }
        )
        self.statusItemController = statusItemController

        dictationController.onRecordingStateChange = {
            [weak statusItemController, weak settingsRuntimeState] isRecording in
            statusItemController?.setRecording(isRecording)
            settingsRuntimeState?.isDictating = isRecording
        }

        // Requests permissions and prepares the selected Speech Model
        // shortly after launch (CONTEXT.md).
        dictationController.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        dictationController?.stop()
    }

    private func showSettings() {
        guard let settings else { return }
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                settings: settings,
                sounds: DictationHUDSounds(),
                runtimeState: settingsRuntimeState
            )
        }
        settingsWindowController?.show()
    }
}
