import CoreGraphics

/// The HUD shape's dimensions at the user's chosen HUD size.
///
/// A full-size shape costs nothing on a MacBook, where the housing band sits
/// behind hardware that already covers those pixels. On a display without a
/// notch every one of those points is screen the user was working in, so the
/// shape scales down as one piece rather than dropping its voice visual.
///
/// The housing band and the fillets are deliberately absent here: neither
/// scales. The housing height is hardware on a notched display and menu-bar
/// clearance everywhere else, and a fillet exists to meet a physical bezel.
struct HUDMetrics: Equatable {
  /// The smallest shape the user can pick.
  ///
  /// At this scale the shape is 216 points wide, which clears a 185-point
  /// notch and both its fillets. A display reporting a wider housing than that
  /// raises its own floor — see `HUDNotchGeometry.minimumScale(for:)` — so this
  /// is the floor for the reference geometry and for every display without a
  /// notch, which is where a smaller HUD is actually wanted: there every point
  /// the shape covers is screen the user was working in.
  static let minimumScale: CGFloat = 0.4
  static let maximumScale: CGFloat = 1

  /// The unscaled shape. The host window is sized from this, so the window
  /// stays fixed while the shape inside it changes size.
  static let standard = HUDMetrics(scale: 1)

  let scale: CGFloat

  init(scale: CGFloat) {
    self.scale = min(max(scale, Self.minimumScale), Self.maximumScale)
  }

  /// The same size, never smaller than `floor`. Used to hold a shape wide
  /// enough for the housing of the display it is actually on.
  func atLeast(_ floor: CGFloat) -> HUDMetrics {
    scale >= floor ? self : HUDMetrics(scale: floor)
  }

  /// Width of the HUD shape; the housing sits centered inside it.
  var contentWidth: CGFloat { 540 * scale }

  /// Height of the strip below the housing where the draft text lives, kept
  /// out of the housing band so text never collides with the camera.
  var textBandHeight: CGFloat { 36 * scale }

  /// The tallest the text band ever gets: the downward-growing long-draft
  /// variant caps at a few wrapped lines.
  var maxTextBandHeight: CGFloat { 120 * scale }

  /// Height of the quiet level-meter strip (the Reduce Motion visual),
  /// shown between the housing and the text band.
  var visualBandHeight: CGFloat { 24 * scale }

  /// Height of the waveform band. The waveform variant replaces the draft
  /// text entirely, so it gets room to breathe.
  var waveBandHeight: CGFloat { 64 * scale }

  var bottomCornerRadius: CGFloat { 20 * scale }
}
