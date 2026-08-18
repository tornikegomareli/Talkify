import CoreGraphics
import Testing
@testable import Talkify

struct HUDNotchGeometryTests {
  private let notched = HUDScreenSnapshot(
    id: 1,
    frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
    safeAreaTop: 32,
    auxiliaryTopLeftArea: CGRect(x: 0, y: 950, width: 663.5, height: 32),
    auxiliaryTopRightArea: CGRect(x: 848.5, y: 950, width: 663.5, height: 32)
  )
  private let external = HUDScreenSnapshot(
    id: 2,
    frame: CGRect(x: 1512, y: 200, width: 2560, height: 1440),
    safeAreaTop: 0,
    auxiliaryTopLeftArea: nil,
    auxiliaryTopRightArea: nil
  )

  @Test func measuresNotchBySubtractingAuxiliaryAreas() {
    let size = HUDNotchGeometry.measuredClosedSize(for: notched)
    #expect(size == CGSize(width: 185, height: 32))
  }

  @Test func measurementIsNilWithoutAuxiliaryAreas() {
    #expect(HUDNotchGeometry.measuredClosedSize(for: external) == nil)
  }

  @Test func measurementIsNilWithZeroSafeArea() {
    let flat = HUDScreenSnapshot(
      id: 3,
      frame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
      safeAreaTop: 0,
      auxiliaryTopLeftArea: CGRect(x: 0, y: 1085, width: 700, height: 32),
      auxiliaryTopRightArea: CGRect(x: 1028, y: 1085, width: 700, height: 32)
    )
    #expect(HUDNotchGeometry.measuredClosedSize(for: flat) == nil)
  }

  @Test func closedSizeFallsBackToSimulatedFootprint() {
    #expect(HUDNotchGeometry.closedSize(for: external) == CGSize(width: 185, height: 32))
  }

  @Test func hasMeasuredNotchReflectsMeasurement() {
    #expect(HUDNotchGeometry.hasMeasuredNotch(for: notched))
    #expect(!HUDNotchGeometry.hasMeasuredNotch(for: external))
  }

  @Test func contentSizeAddsTextBandBelowHousing() {
    let size = HUDNotchGeometry.contentSize(
      for: notched,
      metrics: .standard,
      visualBandHeight: 0,
      includesTextBand: true
    )
    #expect(size == CGSize(width: 540, height: 32 + HUDMetrics.standard.textBandHeight))
  }

  @Test func contentSizeStacksVisualBandAboveText() {
    let size = HUDNotchGeometry.contentSize(
      for: notched,
      metrics: .standard,
      visualBandHeight: HUDMetrics.standard.visualBandHeight,
      includesTextBand: true
    )
    let expected = 32
      + HUDMetrics.standard.visualBandHeight
      + HUDMetrics.standard.textBandHeight
    #expect(size.height == expected)
  }

  @Test func glowListeningLayoutFitsTheFixedWindow() {
    // Both animated visuals use the tall band with no text band while
    // listening; that layout must fit the window without a resize.
    let content = HUDNotchGeometry.contentSize(
      for: notched,
      metrics: .standard,
      visualBandHeight: HUDMetrics.standard.waveBandHeight,
      includesTextBand: false
    )
    let window = HUDNotchGeometry.windowFrame(for: notched)
    #expect(content.height <= window.height - HUDNotchGeometry.shadowPadding)
  }

  @Test func waveOnlyContentSizeDropsTextBand() {
    let size = HUDNotchGeometry.contentSize(
      for: notched,
      metrics: .standard,
      visualBandHeight: HUDMetrics.standard.waveBandHeight,
      includesTextBand: false
    )
    #expect(size.height == 32 + HUDMetrics.standard.waveBandHeight)
  }

  @Test func windowFrameIsBottomCenterWithShadowSlack() {
    let frame = HUDNotchGeometry.windowFrame(for: notched)
    let expectedWidth: CGFloat = 540 + 44 * 2
    let tallestBands = max(
      HUDMetrics.standard.waveBandHeight,
      HUDMetrics.standard.visualBandHeight + HUDMetrics.standard.maxTextBandHeight
    )
    #expect(frame.width == expectedWidth)
    #expect(frame.height == 32 + tallestBands + 44)
    #expect(frame.midX == notched.frame.midX)
    // The HUD floats at the bottom edge, its housing cap flush with it.
    #expect(frame.minY == notched.frame.minY)
  }

  /// Issue #24: the shape shrinks so it stops covering usable screen, but
  /// the housing band does not — it is hardware here and menu-bar clearance
  /// on a display with no notch.
  @Test func hudSizeShrinksTheShapeButNotTheHousing() {
    let small = HUDMetrics(scale: 0.6)
    let size = HUDNotchGeometry.contentSize(
      for: external,
      metrics: small,
      visualBandHeight: small.waveBandHeight,
      includesTextBand: false
    )
    let standard = HUDNotchGeometry.contentSize(
      for: external,
      metrics: .standard,
      visualBandHeight: HUDMetrics.standard.waveBandHeight,
      includesTextBand: false
    )

    #expect(size.width < standard.width)
    #expect(size.height < standard.height)
    #expect(size.height == 32 + small.waveBandHeight)
  }

  /// The shape has to stay wider than the housing it descends from, or it
  /// stops covering the notch it is supposed to hug.
  ///
  /// Enforced per display rather than globally: the slider's own minimum is
  /// meant for displays with no housing to cover, where the band is only menu
  /// bar clearance and nothing is drawn at its stand-in width.
  @Test func smallestShapeOnANotchedDisplayStillCoversItsHousing() {
    let smallest = HUDMetrics(scale: HUDNotchGeometry.minimumScale(for: notched))
    #expect(smallest.contentWidth > HUDNotchGeometry.closedSize(for: notched).width)
  }

  /// ADR-0001's fixed host window: the frame is the standard envelope
  /// whatever the user's HUD size, so a smaller shape centers inside it
  /// instead of resizing the window mid-session.
  @Test func windowFrameIgnoresHUDSize() {
    let frame = HUDNotchGeometry.windowFrame(for: external)
    let smallest = HUDMetrics(scale: HUDMetrics.minimumScale)
    let content = HUDNotchGeometry.contentSize(
      for: external,
      metrics: smallest,
      visualBandHeight: smallest.visualBandHeight,
      includesTextBand: true
    )

    let standardWidth: CGFloat = 540 + 44 * 2
    #expect(frame.width == standardWidth)
    #expect(content.width < frame.width)
    #expect(content.height < frame.height)
  }

  @Test func windowFrameClampsToNarrowScreen() {
    let narrow = HUDScreenSnapshot(
      id: 4,
      frame: CGRect(x: 0, y: 0, width: 600, height: 800),
      safeAreaTop: 0,
      auxiliaryTopLeftArea: nil,
      auxiliaryTopRightArea: nil
    )
    let frame = HUDNotchGeometry.windowFrame(for: narrow)
    #expect(frame.width == 600)
    #expect(frame.midX == 300)
  }

  @Test func filletsExistOnlyAgainstRealHousing() {
    #expect(HUDNotchGeometry.filletSize(for: notched) > 0)
    #expect(HUDNotchGeometry.filletSize(for: external) == 0)
  }

  @Test func glowSweepFollowsHousingFillets() {
    let size = CGSize(width: 600, height: 120)
    let start = HUDGlowSilhouetteShape.point(
      atArcFraction: 0,
      cornerRadius: HUDMetrics.standard.bottomCornerRadius,
      topFilletRadius: HUDNotchGeometry.filletSize(for: notched),
      inset: 28,
      in: size
    )
    let end = HUDGlowSilhouetteShape.point(
      atArcFraction: 1,
      cornerRadius: HUDMetrics.standard.bottomCornerRadius,
      topFilletRadius: HUDNotchGeometry.filletSize(for: notched),
      inset: 28,
      in: size
    )

    // With the housing cap at the bottom edge, the fillets the glow hugs
    // sit at the bottom corners of the shape.
    #expect(start == CGPoint(x: 17, y: 120))
    #expect(end == CGPoint(x: 583, y: 120))
  }
}
