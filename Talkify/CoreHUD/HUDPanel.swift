import AppKit

/// The window that hosts the HUD.
///
/// Sits at `mainMenu + 3` — enough to own the notch strip above the menu bar
/// and full-screen apps without private-API window code (ADR-0001).
final class HUDPanel: NSPanel {
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
    // Display-only during dictation: clicks pass through everywhere and it
    // never takes focus. Drop Transcription flips this on while the shape is a
    // drop target or holding a transcript, and off again afterwards.
    ignoresMouseEvents = true
    hidesOnDeactivate = false
    isReleasedWhenClosed = false
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    self.contentView = contentView
  }

  /// Whether the shape currently receives the mouse. Kept as a named property
  /// rather than callers setting `ignoresMouseEvents` directly, so the one
  /// place this is allowed to change stays greppable.
  var acceptsMouse: Bool {
    get { !ignoresMouseEvents }
    set { ignoresMouseEvents = !newValue }
  }

  /// Whether the panel may become key for the editable-draft review — the
  /// dictation occupant's own key surface, set by `HUDStage` while the
  /// draft is held for editing and cleared again when the shape goes away.
  var acceptsKey = false

  /// Key only while the shape wants keyboard or mouse: as a drop target,
  /// holding a transcript, or holding an editable draft.
  ///
  /// NotchDrop's window can become key and its drops land instantly; a window
  /// that can never become key is a slower path for the dragging source. The
  /// panel is still `.nonactivatingPanel`, so this never activates Talkify or
  /// takes the frontmost app's focus — and during dictation, when the focused
  /// control is the whole point, `acceptsMouse` is false and this is false
  /// with it.
  override var canBecomeKey: Bool { acceptsMouse || acceptsKey }

  /// The frame is computed from the screen, not proposed by AppKit; without
  /// this the window gets pushed below the menu bar strip it exists to cover.
  override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
    frameRect
  }
}
