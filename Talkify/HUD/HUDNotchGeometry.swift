import CoreGraphics

/// Frames for the Direct Dictation HUD, lifted from Tilebar's NotchIsland
/// pattern (ADR-0001): a fixed-size host window pinned to the top center whose
/// origin moves but never resizes, and a measured-vs-simulated notch split.
enum HUDNotchGeometry {
  /// Stand-in footprint for a display that reports no notch (ADR-0001).
  /// The menu-bar height is not a usable substitute — auto-hidden it
  /// measures zero, which would collapse the housing to nothing.
  static let fallbackClosedSize = CGSize(width: 185, height: 32)

  /// Width of the HUD shape; the housing sits centered inside it.
  static let contentWidth: CGFloat = 540

  /// Height of the strip below the housing where the draft text lives, kept
  /// out of the housing band so text never collides with the camera.
  static let textBandHeight: CGFloat = 36

  /// The tallest the text band ever gets: the downward-growing long-draft
  /// variant caps at a few wrapped lines. The host window is sized for this
  /// so growth never needs a window resize.
  static let maxTextBandHeight: CGFloat = 120

  /// Height of the quiet level-meter strip (the Reduce Motion visual),
  /// shown between the housing and the text band.
  static let visualBandHeight: CGFloat = 24

  /// Height of the waveform band. The waveform variant replaces the draft
  /// text entirely, so it gets room to breathe.
  static let waveBandHeight: CGFloat = 64

  /// Slack on the left, right, and bottom so the shell's drawn shadow is not
  /// clipped by the fixed window frame. Nothing is added at the top: that
  /// edge is the top of the screen and the shape is flush against it.
  static let shadowPadding: CGFloat = 44

  static let bottomCornerRadius: CGFloat = 20

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

  /// The housing footprint, falling back to the simulated stand-in.
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
    visualBandHeight: CGFloat,
    includesTextBand: Bool
  ) -> CGSize {
    CGSize(
      width: min(contentWidth, windowFrame(for: screen).width),
      height: closedSize(for: screen).height
        + visualBandHeight
        + (includesTextBand ? textBandHeight : 0)
    )
  }

  /// Size of the concave corner that flares the shape into the bezel, and
  /// zero on a display with no housing to flare into — there the curve reads
  /// as two detached tabs (ADR-0001: the simulated notch omits fillets).
  static func filletSize(for screen: HUDScreenSnapshot) -> CGFloat {
    hasMeasuredNotch(for: screen) ? 11 : 0
  }

  /// The host window's frame: content size plus shadow slack, centered and
  /// pinned to the top, clamped to the screen width.
  static func windowFrame(for screen: HUDScreenSnapshot) -> CGRect {
    let width = min(contentWidth + shadowPadding * 2, screen.frame.width)
    let height = closedSize(for: screen).height
      + max(waveBandHeight, visualBandHeight + maxTextBandHeight)
      + shadowPadding

    return CGRect(
      x: screen.frame.midX - width / 2,
      y: screen.frame.maxY - height,
      width: width,
      height: height
    )
  }
}
