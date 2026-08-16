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

  /// How far the pointer may go before an open target gives up, measured the
  /// same way.
  ///
  /// Deliberately much larger than the band that opens it, and for a concrete
  /// reason: the band is a narrow strip near the notch, but what it opens is a
  /// shape roughly 110 points deep and up to 540 wide. Judging both with one
  /// number meant the target closed while the pointer was still on the shape it
  /// had just opened — a small move mid-drag and the HUD vanished. These cover
  /// the opened shape at full HUD size, plus margin so resting on its edge does
  /// not flicker.
  static let holdHeight: CGFloat = 170
  static let holdReach: CGFloat = 330

  /// The zone after moving to `point`, given where the drag already was.
  ///
  /// The gesture is progressive on the way in and sticky once it lands: an
  /// open target holds until the pointer is clear of the shape, and it never
  /// falls back to a peek. Collapsing to a hint while the user is still over
  /// the thing they are aiming at reads as the target refusing them.
  ///
  /// `point` and `frame` are both in AppKit screen coordinates, whose origin
  /// is the bottom-left of the main display, so the top edge is `maxY`.
  static func next(after current: DropZone, at point: CGPoint, in frame: CGRect) -> DropZone {
    let depth = frame.maxY - point.y
    let offset = abs(point.x - frame.midX)
    guard depth >= 0 else { return .outside }

    if current == .open {
      return depth <= holdHeight && offset <= holdReach ? .open : .outside
    }
    if depth <= openHeight, offset <= openReach { return .open }
    if depth <= peekHeight, offset <= peekReach { return .peek }
    return .outside
  }
}
