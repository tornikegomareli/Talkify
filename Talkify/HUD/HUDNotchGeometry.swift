import CoreGraphics

/// Frames for the Direct Dictation HUD, lifted from Tilebar's NotchIsland
/// pattern (ADR-0001): a fixed-size host window pinned to the top center whose
/// origin moves but never resizes, and a measured-vs-simulated notch split.
///
/// What this type decides is what the *display* imposes: the housing
/// footprint, whether fillets exist, and the host window. Everything the user
/// can resize lives in `HUDMetrics`.
enum HUDNotchGeometry {
  /// Stand-in footprint for a display that reports no notch (ADR-0001).
  /// The menu-bar height is not a usable substitute — auto-hidden it
  /// measures zero, which would collapse the housing to nothing.
  static let fallbackClosedSize = CGSize(width: 185, height: 32)

  /// Slack on the left, right, and bottom so the shell's drawn shadow is not
  /// clipped by the fixed window frame. Nothing is added at the top: that
  /// edge is the top of the screen and the shape is flush against it.
  static let shadowPadding: CGFloat = 44

  /// The notch this display actually reports, or nil when there is nothing
  /// to measure. Width comes from the two auxiliary areas by subtraction so
  /// the result does not depend on which coordinate space they arrive in.
  ///
  /// Optional rather than falling back here, because whether a measurement
  /// succeeded cannot be recovered from its result: a 14" MacBook Pro
  /// measures exactly the fallback numbers.
  static func measuredClosedSize(for screen: HUDScreenSnapshot) -> CGSize? {
    guard
      let left = screen.auxiliaryTopLeftArea,
      let right = screen.auxiliaryTopRightArea,
      screen.safeAreaTop > 0
    else {
      return nil
    }

    let width = screen.frame.width - left.width - right.width
    guard width > 0, width < screen.frame.width else { return nil }

    return CGSize(width: width, height: screen.safeAreaTop)
  }

  /// The housing footprint, falling back to the simulated stand-in. Never
  /// scaled by the HUD size: this height is hardware on a notched display,
  /// and the menu bar's clearance on every other one.
  static func closedSize(for screen: HUDScreenSnapshot) -> CGSize {
    measuredClosedSize(for: screen) ?? fallbackClosedSize
  }

  /// Whether this display has a housing of its own for the HUD to hug.
  static func hasMeasuredNotch(for screen: HUDScreenSnapshot) -> Bool {
    measuredClosedSize(for: screen) != nil
  }

  /// The HUD shape's size: the housing band, whatever voice-visual band the
  /// selected visual uses, and the text band unless the visual replaces it,
  /// clamped so a narrow display never gets a shape wider than its window.
  static func contentSize(
    for screen: HUDScreenSnapshot,
    metrics: HUDMetrics,
    visualBandHeight: CGFloat,
    includesTextBand: Bool
  ) -> CGSize {
    CGSize(
      width: min(metrics.contentWidth, windowFrame(for: screen).width),
      height: closedSize(for: screen).height
        + visualBandHeight
        + (includesTextBand ? metrics.textBandHeight : 0)
    )
  }

  /// Breathing room each side of the housing, so the shape reads as wider than
  /// what it descends from rather than exactly as wide as it.
  static let housingShoulder: CGFloat = 4

  /// The smallest scale this display can show.
  ///
  /// A shape narrower than the housing stops reading as the notch growing and
  /// becomes a tab floating under it, and its fillets land inside the cutout
  /// where there is no bezel to flare into. So a measured notch sets its own
  /// floor from its real width. A display without a notch has nothing to cover
  /// and keeps the global minimum.
  ///
  /// This only ever raises the floor, and on the common notches it does not
  /// raise it at all — it exists so an unusually wide housing cannot produce a
  /// detached tab.
  static func minimumScale(for screen: HUDScreenSnapshot) -> CGFloat {
    guard hasMeasuredNotch(for: screen) else { return HUDMetrics.minimumScale }
    let needed = closedSize(for: screen).width
      + filletSize(for: screen) * 2
      + housingShoulder * 2
    let scale = needed / HUDMetrics.standard.contentWidth
    return min(max(scale, HUDMetrics.minimumScale), HUDMetrics.maximumScale)
  }

  /// Size of the concave corner that flares the shape into the bezel, and
  /// zero on a display with no housing to flare into — there the curve reads
  /// as two detached tabs (ADR-0001: the simulated notch omits fillets).
  /// Unscaled: the flare has to match a physical bezel curve.
  static func filletSize(for screen: HUDScreenSnapshot) -> CGFloat {
    hasMeasuredNotch(for: screen) ? 11 : 0
  }

  /// The host window's frame: content size plus shadow slack, centered and
  /// pinned to the top, clamped to the screen width.
  ///
  /// Sized for the standard metrics whatever the user's HUD size, so the
  /// window stays fixed per display (ADR-0001) and a smaller shape simply
  /// centers itself inside it. The window is invisible and click-through, so
  /// the unused slack costs nothing.
  static func windowFrame(for screen: HUDScreenSnapshot) -> CGRect {
    let metrics = HUDMetrics.standard
    let width = min(metrics.contentWidth + shadowPadding * 2, screen.frame.width)
    let height = closedSize(for: screen).height
      + max(metrics.waveBandHeight, metrics.visualBandHeight + metrics.maxTextBandHeight)
      + shadowPadding

    return CGRect(
      x: screen.frame.midX - width / 2,
      y: screen.frame.maxY - height,
      width: width,
      height: height
    )
  }
}
