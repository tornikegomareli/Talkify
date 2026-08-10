import AppKit
import SwiftUI

/// Lets the borderless Settings window be dragged by its header (CONTEXT.md:
/// the fixed surface moves by its header; content stays non-draggable).
struct SettingsWindowDragHandle: NSViewRepresentable {
  func makeNSView(context: Context) -> NSView {
    SettingsWindowDragView()
  }

  func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class SettingsWindowDragView: NSView {
  override func mouseDown(with event: NSEvent) {
    window?.performDrag(with: event)
  }
}
