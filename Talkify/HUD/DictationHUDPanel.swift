import AppKit

/// The window that hosts the HUD.
///
/// Sits at `mainMenu + 3` — enough to own the notch strip above the menu bar
/// and full-screen apps without private-API window code (ADR-0001).
final class DictationHUDPanel: NSPanel {
  init(contentRect: NSRect, contentView: NSView) {
    super.init(
      contentRect: contentRect,
      styleMask: [.nonactivatingPanel],
      backing: .buffered,
      defer: false
    )

    level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
    isOpaque = false
    backgroundColor = .clear
    // The shell draws the design's shadow itself, so window shadow would
    // double it.
    hasShadow = false
    isMovable = false
    isMovableByWindowBackground = false
    // Display-only: clicks pass through everywhere and it never takes focus.
    ignoresMouseEvents = true
    hidesOnDeactivate = false
    isReleasedWhenClosed = false
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    self.contentView = contentView
  }

  /// The frame is computed from the screen, not proposed by AppKit; without
  /// this the window gets pushed below the menu bar strip it exists to cover.
  override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
    frameRect
  }
}
