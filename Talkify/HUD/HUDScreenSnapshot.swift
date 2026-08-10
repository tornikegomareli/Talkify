import CoreGraphics

/// Pure geometry of one display, captured from `NSScreen` so the notch math
/// and display selection stay UI-free and testable.
struct HUDScreenSnapshot: Equatable, Sendable {
  let id: CGDirectDisplayID
  /// Global screen coordinates (bottom-left origin, y up).
  let frame: CGRect
  let safeAreaTop: CGFloat
  let auxiliaryTopLeftArea: CGRect?
  let auxiliaryTopRightArea: CGRect?
}
