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
