import CoreGraphics
import Testing
@testable import Talkify

struct HUDNotchGeometryTests {
  private let notched = HUDScreenSnapshot(
    id: 1,
    frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
    safeAreaTop: 32,
    auxiliaryTopLeftArea: CGRect(x: 0, y: 950, width: 663.5, height: 32),
    auxiliaryTopRightArea: CGRect(x: 848.5, y: 950, width: 663.5, height: 32),
    menuBarHeight: 32
  )
  private let external = HUDScreenSnapshot(
    id: 2,
    frame: CGRect(x: 1512, y: 200, width: 2560, height: 1440),
    safeAreaTop: 0,
    auxiliaryTopLeftArea: nil,
    auxiliaryTopRightArea: nil,
    menuBarHeight: 24
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
      auxiliaryTopRightArea: CGRect(x: 1028, y: 1085, width: 700, height: 32),
      menuBarHeight: 32
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
      includesTextBand: true,
      shapingBandHeight: 0
    )
    #expect(size == CGSize(width: 540, height: 32 + HUDMetrics.standard.textBandHeight))
  }

  @Test func contentSizeStacksVisualBandAboveText() {
    let size = HUDNotchGeometry.contentSize(
      for: notched,
      metrics: .standard,
      visualBandHeight: HUDMetrics.standard.visualBandHeight,
      includesTextBand: true,
      shapingBandHeight: 0
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
      includesTextBand: false,
      shapingBandHeight: 0
    )
    let window = HUDNotchGeometry.windowFrame(for: notched, clearsMenuBar: false)
    #expect(content.height <= window.height - HUDNotchGeometry.shadowPadding)
  }

  @Test func waveOnlyContentSizeDropsTextBand() {
    let size = HUDNotchGeometry.contentSize(
      for: notched,
      metrics: .standard,
      visualBandHeight: HUDMetrics.standard.waveBandHeight,
      includesTextBand: false,
      shapingBandHeight: 0
    )
    #expect(size.height == 32 + HUDMetrics.standard.waveBandHeight)
  }

  @Test func windowFrameIsTopCenterWithShadowSlack() {
    let frame = HUDNotchGeometry.windowFrame(for: notched, clearsMenuBar: false)
    let expectedWidth: CGFloat = 540 + 44 * 2
    // The shaping band rides outside the max: it can hang under either band
    // stack, so the tallest layout is whichever stack wins plus it.
    let tallestBands = max(
      HUDMetrics.standard.waveBandHeight,
      HUDMetrics.standard.visualBandHeight + HUDMetrics.standard.maxTextBandHeight
    ) + HUDMetrics.standard.shapingBandHeight
    #expect(frame.width == expectedWidth)
    #expect(frame.height == 32 + tallestBands + 44)
    #expect(frame.midX == notched.frame.midX)
    #expect(frame.maxY == notched.frame.maxY)
  }

  @Test func contentSizeAddsTheShapingLabelBelowTheOtherBands() {
    let size = HUDNotchGeometry.contentSize(
      for: notched,
      metrics: .standard,
      visualBandHeight: HUDMetrics.standard.visualBandHeight,
      includesTextBand: true,
      shapingBandHeight: HUDMetrics.standard.shapingBandHeight
    )
    let expected = 32
      + HUDMetrics.standard.visualBandHeight
      + HUDMetrics.standard.textBandHeight
      + HUDMetrics.standard.shapingBandHeight
    #expect(size.height == expected)
  }

  /// The tallest layout a shaping session can show — the quiet visual band, a
  /// four-line draft, and the shaping label under both — must fit the fixed
  /// window, which never resizes (ADR-0001).
  @Test func tallestShapingLayoutFitsTheFixedWindow() {
    let window = HUDNotchGeometry.windowFrame(for: notched, clearsMenuBar: false)
    let tallest = 32
      + HUDMetrics.standard.visualBandHeight
      + HUDMetrics.standard.maxTextBandHeight
      + HUDMetrics.standard.shapingBandHeight
    #expect(tallest <= window.height - HUDNotchGeometry.shadowPadding)
  }

  /// Edge Glow + Draft has no dedicated visual band: the hanging stage
  /// replaces the ordinary text band. Housing plus that stage plus shaping
  /// still fits; a concert waveform on top of the draft would not.
  @Test func glowDraftMaximumStackFitsTheFixedWindow() {
    let window = HUDNotchGeometry.windowFrame(for: notched, clearsMenuBar: false)
    let glowDraft = 32
      + HUDMetrics.standard.glowDraftStageHeight
      + HUDMetrics.standard.shapingBandHeight
    #expect(glowDraft <= window.height - HUDNotchGeometry.shadowPadding)
    let concertPlusDraft = 32
      + HUDMetrics.standard.waveBandHeight
      + HUDMetrics.standard.maxTextBandHeight
      + HUDMetrics.standard.shapingBandHeight
    #expect(concertPlusDraft > window.height - HUDNotchGeometry.shadowPadding)
  }

  /// Issue #83: a real notch already sits in its own housing, clear of
  /// wherever the system draws status items, so there is nothing for the
  /// shape to hide there — it keeps hugging the true top edge.
  /// The preference only governs a display with no housing. A notched one
  /// hugs its own notch either way.
  @Test func aNotchedDisplayIgnoresTheMenuBarPreference() {
    #expect(HUDNotchGeometry.topInset(for: notched, clearsMenuBar: true) == 0)
    #expect(HUDNotchGeometry.topInset(for: notched, clearsMenuBar: false) == 0)
  }

  /// Off, the shape sits where the notch would be, which is what it imitates.
  @Test func aDisplayWithNoNotchSitsOverTheMenuBarByDefault() {
    #expect(HUDNotchGeometry.topInset(for: external, clearsMenuBar: false) == 0)
    #expect(
      HUDNotchGeometry.windowFrame(for: external, clearsMenuBar: false).maxY
        == external.frame.maxY
    )
  }

  @Test func topInsetIsZeroOnANotchedDisplay() {
    #expect(HUDNotchGeometry.topInset(for: notched, clearsMenuBar: true) == 0)
  }

  /// Issue #83: with no real notch to hug, a shape pinned flush to the
  /// screen's top edge draws directly over the menu bar — hiding whatever
  /// status item sits under it, including Talkify's own. Clearing the menu
  /// bar's own height keeps the shape below it instead.
  @Test func topInsetMatchesTheMenuBarOnADisplayWithNoNotch() {
    #expect(HUDNotchGeometry.topInset(for: external, clearsMenuBar: true) == external.menuBarHeight)
  }

  @Test func windowFrameHangsBelowTheMenuBarWithNoNotch() {
    let frame = HUDNotchGeometry.windowFrame(for: external, clearsMenuBar: true)
    #expect(frame.maxY == external.frame.maxY - external.menuBarHeight)
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
      includesTextBand: false,
      shapingBandHeight: 0
    )
    let standard = HUDNotchGeometry.contentSize(
      for: external,
      metrics: .standard,
      visualBandHeight: HUDMetrics.standard.waveBandHeight,
      includesTextBand: false,
      shapingBandHeight: 0
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
    let frame = HUDNotchGeometry.windowFrame(for: external, clearsMenuBar: true)
    let smallest = HUDMetrics(scale: HUDMetrics.minimumScale)
    let content = HUDNotchGeometry.contentSize(
      for: external,
      metrics: smallest,
      visualBandHeight: smallest.visualBandHeight,
      includesTextBand: true,
      shapingBandHeight: 0
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
      auxiliaryTopRightArea: nil,
      menuBarHeight: 24
    )
    let frame = HUDNotchGeometry.windowFrame(for: narrow, clearsMenuBar: false)
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

    #expect(start == CGPoint(x: 17, y: 0))
    #expect(end == CGPoint(x: 583, y: 0))
  }
}
