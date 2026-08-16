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
  /// The drag ended, wherever it ended.
  var onDragEnd: (() -> Void)?

  private var monitor: Any?
  private var isTracking = false
  private var draggedURL: URL?
  private var zone = DropZone.outside

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
      let wasEngaged = zone != .outside
      reset()
      if wasEngaged { onDragEnd?() }
    case .leftMouseDragged:
      trackDrag()
    default:
      break
    }
  }

  private func trackDrag() {
    if !isTracking {
      isTracking = true
      // Read the drag pasteboard once per drag rather than per event: it
      // cannot change mid-drag, and this fires at pointer rate.
      draggedURL = Self.transcribableURL()
    }
    guard let draggedURL else { return }

    let point = NSEvent.mouseLocation
    let frame = Self.screenFrame(containing: point)
    let next = DropZone.at(point, in: frame)
    guard next != zone else { return }
    zone = next
    onZoneChange?(next, draggedURL)
  }

  private func reset() {
    isTracking = false
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
    let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
    return screen?.frame ?? .zero
  }
}
