import AppKit
import Testing
@testable import Talkify

@MainActor
struct SettingsWindowTests {
    @Test func controllerBuildsATitledClosableWindow() throws {
        let settings = AppSettings.previewStore()
        let controller = SettingsWindowController(
            settings: settings,
            sounds: DictationHUDSounds(settings: settings)
        )
        let window = try #require(controller.window)
        #expect(window.title == "Talkify Settings")
        #expect(window.styleMask.contains(.closable))
        #expect(!window.isReleasedWhenClosed)
    }
}
