import AppKit

// Reconstructed helper: the original file was lost in the cleanup. TextInsertionService
// (and the old HUD) call `screen.cgDirectDisplayID`; this is the standard implementation.
extension NSScreen {
    var cgDirectDisplayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
