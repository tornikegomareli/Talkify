/// What the HUD does when the draft outgrows one line. CONTEXT.md flags this
/// as undecided; all three variants stay selectable until the pick is made
/// by feel.
enum HUDLongDraftStyle: String, CaseIterable {
  /// One line, newest words visible, head truncated.
  case tailOnly = "Tail Only"
  /// Text wraps and the shape grows downward with it, capped at a few
  /// lines. The host window is already sized for the cap.
  case growDown = "Grow Down"
  /// One line whose font shrinks as the draft grows, truncating only after
  /// the scale floor is hit.
  case shrinkToFit = "Shrink to Fit"
}
