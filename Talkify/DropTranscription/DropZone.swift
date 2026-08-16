import CoreGraphics

/// Where a dragged file's pointer is, relative to the notch.
///
/// The gesture is progressive: crossing into the top of the screen makes the
/// island peek, and continuing toward the notch opens it into a target. The
/// catch area is far wider than the notch so the gesture is "throw it at the
/// top of the screen" rather than "hit a 185-point strip".
enum DropZone: Equatable {
  case outside
  /// Close enough to hint, not close enough to receive.
  case peek
  /// Open, and accepting the drop.
  case open

  /// Height of the band that starts the peek, measured down from the top of
  /// the display.
  static let peekHeight: CGFloat = 140
  /// Half-width of the peek band, measured out from the display's horizontal
  /// center.
  static let peekReach: CGFloat = 420
  static let openHeight: CGFloat = 64
  static let openReach: CGFloat = 260

  /// `point` and `frame` are both in AppKit screen coordinates, whose origin
  /// is the bottom-left of the main display, so the top edge is `maxY`.
  static func at(_ point: CGPoint, in frame: CGRect) -> DropZone {
    let depth = frame.maxY - point.y
    let offset = abs(point.x - frame.midX)
    guard depth >= 0 else { return .outside }

    if depth <= openHeight, offset <= openReach { return .open }
    if depth <= peekHeight, offset <= peekReach { return .peek }
    return .outside
  }
}
