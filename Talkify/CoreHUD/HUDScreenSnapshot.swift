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
  /// This display's own reserved strip for the system menu bar, i.e. `frame`
  /// minus `visibleFrame` at the top. Zero on a display that shows no menu
  /// bar of its own. Distinct from `safeAreaTop`: that is the *notch*, a
  /// housing the HUD hugs; this is the *menu bar*, a bar of status items the
  /// HUD must clear (issue #83).
  let menuBarHeight: CGFloat
}
