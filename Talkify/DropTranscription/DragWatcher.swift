import AppKit

/// Notices that a media file is being dragged toward the notch.
///
/// macOS tells a background app nothing about a drag until it enters a window
/// that accepts one, and a window stretched across the top of the screen would
/// either swallow menu-bar clicks or, made click-through, receive nothing. So
/// the drag is watched globally instead and the HUD becomes a real drop target
/// only once the pointer is close.
///
/// Reacting to every drag on the system is intrusive — Yoink makes it opt-in
/// and Dropover requires a deliberate shake — so nothing is shown until the
/// pointer reaches the top of the display.
@MainActor
final class DragWatcher {
  /// The zone changed while dragging a transcribable file.
  var onZoneChange: ((DropZone, URL) -> Void)?
  /// The drag ended, with the zone the pointer was in when the button came up.
  /// A release over the open target is a drop, and the caller must leave that
  /// one alone: the HUD is the destination AppKit is delivering to.
  var onDragEnd: ((DropZone) -> Void)?

  private var monitor: Any?
  private var draggedURL: URL?
  private var zone = DropZone.outside
  private let dragPasteboard = NSPasteboard(name: .drag)
  /// Which drag the pasteboard was last read for. Every drag bumps the count,
  /// so this both avoids re-reading at pointer rate and keeps one drag's
  /// contents from answering for the next one's.
  private var readChangeCount = -1

  func start() {
    guard monitor == nil else { return }
    monitor = NSEvent.addGlobalMonitorForEvents(
      matching: [.leftMouseDragged, .leftMouseUp]
    ) { [weak self] event in
      MainActor.assumeIsolated {
        self?.handle(event)
      }
    }
  }

  func stop() {
    if let monitor { NSEvent.removeMonitor(monitor) }
    monitor = nil
    reset()
  }

  private func handle(_ event: NSEvent) {
    switch event.type {
    case .leftMouseUp:
      let endedIn = zone
      reset()
      if endedIn != .outside { onDragEnd?(endedIn) }
    case .leftMouseDragged:
      trackDrag()
    default:
      break
    }
  }

  private func trackDrag() {
    // The pasteboard is not written the instant the button goes down: the
    // first mouse-dragged events of a gesture arrive before the drag has
    // officially begun. Reading once and keeping the answer meant a nil read
    // there disarmed the whole drag, which is why the first attempt after
    // launch never revealed the HUD and the second one — reading the previous
    // drag's leftovers — did.
    if dragPasteboard.changeCount != readChangeCount {
      readChangeCount = dragPasteboard.changeCount
      draggedURL = Self.transcribableURL(on: dragPasteboard)
    }
    guard let draggedURL else { return }

    let point = NSEvent.mouseLocation
    let frame = Self.screenFrame(containing: point)
    let next = DropZone.next(after: zone, at: point, in: frame)
    guard next != zone else { return }
    zone = next
    onZoneChange?(next, draggedURL)
  }

  private func reset() {
    draggedURL = nil
    zone = .outside
  }

  /// The dragged file, when there is exactly one and it is audio or video.
  /// A multi-file drag is refused rather than silently transcribing the first:
  /// one job at a time, and guessing which one is worse than declining.
  static func transcribableURL(
    on pasteboard: NSPasteboard = NSPasteboard(name: .drag)
  ) -> URL? {
    guard let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
          urls.count == 1,
          let url = urls.first,
          MediaFileTypes.isTranscribable(url: url)
    else {
      return nil
    }
    return url
  }

  private static func screenFrame(containing point: CGPoint) -> CGRect {
    // The top row of pixels is where this gesture ends, and `contains` excludes
    // a rect's max edge, so a pointer exactly on a screen's top edge belongs to
    // no screen at all. Probe one point lower before asking.
    let probe = CGPoint(x: point.x, y: point.y - 1)
    let screen = NSScreen.screens.first { $0.frame.contains(probe) } ?? NSScreen.main
    return screen?.frame ?? .zero
  }
}
