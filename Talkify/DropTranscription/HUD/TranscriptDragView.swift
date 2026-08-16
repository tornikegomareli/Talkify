import AppKit
import SwiftUI

/// The card's two gestures: drag it out as a file, or click it to take the
/// transcript as text.
///
/// SwiftUI's `draggable` cannot say whether a drag was accepted, and that answer
/// decides where the transcript is saved — a drag a destination takes is the
/// user choosing where it goes, and a drag let go over nothing has to leave the
/// card exactly as it was. So the drag starts from an `NSDraggingSource`, which
/// reports the operation the receiver performed.
struct TranscriptDragView: NSViewRepresentable {
  let url: URL
  let text: String
  /// Built when the drag starts rather than on every card update: the card
  /// redraws while its dismissal hairline drains, and rendering an image twenty
  /// times a second to maybe never use it is waste.
  let makeDragImage: @MainActor () -> NSImage?
  var onEvent: (HUDCardEvent) -> Void

  func makeNSView(context: Context) -> TranscriptDragSourceView {
    TranscriptDragSourceView()
  }

  func updateNSView(_ view: TranscriptDragSourceView, context: Context) {
    view.url = url
    view.text = text
    view.makeDragImage = makeDragImage
    view.onEvent = onEvent
  }
}

/// Transparent, sized by SwiftUI, and the only part of the HUD that has ever
/// wanted the mouse for something other than a drop.
final class TranscriptDragSourceView: NSView, NSDraggingSource {
  /// How far the pointer may wander before a press counts as a drag rather
  /// than a click. Without slack, a click with an unsteady hand copies nothing
  /// and starts a drag nobody asked for.
  private static let dragSlack: CGFloat = 4

  var url: URL?
  var text = ""
  var makeDragImage: (@MainActor () -> NSImage?)?
  var onEvent: ((HUDCardEvent) -> Void)?

  private var trackingArea: NSTrackingArea?
  private var pressOrigin: CGPoint?
  /// The cursor stack has to be balanced by hand: a drag steals the pointer
  /// without sending `mouseExited`, and an unpopped cursor is an open hand over
  /// every app until the next relaunch.
  private var hasPushedCursor = false

  /// The HUD's panel never activates Talkify, so the first press has to work
  /// while the app is in the background — which is every time.
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let trackingArea { removeTrackingArea(trackingArea) }
    let area = NSTrackingArea(
      rect: .zero,
      options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
      owner: self
    )
    addTrackingArea(area)
    trackingArea = area
  }

  override func viewWillMove(toWindow newWindow: NSWindow?) {
    super.viewWillMove(toWindow: newWindow)
    if newWindow == nil { popCursor() }
  }

  override func mouseEntered(with event: NSEvent) {
    onEvent?(.hover(true))
    pushCursor()
  }

  override func mouseExited(with event: NSEvent) {
    onEvent?(.hover(false))
    popCursor()
  }

  override func mouseDown(with event: NSEvent) {
    pressOrigin = event.locationInWindow
  }

  /// A press that never travelled is a click, which asks for the transcript as
  /// text rather than as a file.
  override func mouseUp(with event: NSEvent) {
    guard pressOrigin != nil else { return }
    pressOrigin = nil
    onEvent?(.clicked)
  }

  override func mouseDragged(with event: NSEvent) {
    guard let url, let origin = pressOrigin else { return }
    let travelled = hypot(
      event.locationInWindow.x - origin.x,
      event.locationInWindow.y - origin.y
    )
    guard travelled > Self.dragSlack else { return }
    pressOrigin = nil

    // Two flavors, one drag. Finder and any folder take the file and write the
    // .txt; a text field takes the words. Which one a receiver wants is a
    // question only that receiver can answer, so both are offered and neither
    // is chosen here (docs/design/FEATURE.md).
    let contents = NSPasteboardItem()
    contents.setString(url.absoluteString, forType: .fileURL)
    contents.setString(text, forType: .string)
    let item = NSDraggingItem(pasteboardWriter: contents)
    let image = makeDragImage?()
    let size = image?.size ?? bounds.size
    item.setDraggingFrame(
      CGRect(
        x: bounds.midX - size.width / 2,
        y: bounds.midY - size.height / 2,
        width: size.width,
        height: size.height
      ),
      contents: image
    )
    _ = beginDraggingSession(with: [item], event: event, source: self)
  }

  /// Copy only. The dragged file sits in a temporary folder the user never
  /// sees, so moving it out of there would mean nothing to them; Talkify
  /// removes the folder itself once a destination has taken the transcript.
  func draggingSession(
    _ session: NSDraggingSession,
    sourceOperationMaskFor context: NSDraggingContext
  ) -> NSDragOperation {
    context == .outsideApplication ? .copy : []
  }

  func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
    onEvent?(.dragBegan)
  }

  func draggingSession(
    _ session: NSDraggingSession,
    endedAt screenPoint: NSPoint,
    operation: NSDragOperation
  ) {
    popCursor()
    onEvent?(.dragEnded(handled: operation != []))
  }

  private func pushCursor() {
    guard !hasPushedCursor else { return }
    hasPushedCursor = true
    NSCursor.openHand.push()
  }

  private func popCursor() {
    guard hasPushedCursor else { return }
    hasPushedCursor = false
    NSCursor.pop()
  }
}
