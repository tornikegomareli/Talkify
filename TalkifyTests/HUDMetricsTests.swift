import CoreGraphics
import Testing
@testable import Talkify

struct HUDMetricsTests {
  @Test func standardIsTheUnscaledShape() {
    #expect(HUDMetrics.standard.scale == 1)
    #expect(HUDMetrics.standard.contentWidth == 540)
    #expect(HUDMetrics.standard.waveBandHeight == 64)
  }

  @Test func everyDimensionScalesTogether() {
    let half = HUDMetrics(scale: 0.8)
    let full = HUDMetrics.standard

    #expect(half.contentWidth == full.contentWidth * 0.8)
    #expect(half.textBandHeight == full.textBandHeight * 0.8)
    #expect(half.maxTextBandHeight == full.maxTextBandHeight * 0.8)
    #expect(half.visualBandHeight == full.visualBandHeight * 0.8)
    #expect(half.waveBandHeight == full.waveBandHeight * 0.8)
    #expect(half.bottomCornerRadius == full.bottomCornerRadius * 0.8)
  }

  /// The scale arrives from a stored preference, so a value from an older
  /// build or a hand-edited defaults file comes back clamped rather than
  /// producing a shape nobody can read.
  @Test func scaleIsClampedToItsSupportedRange() {
    #expect(HUDMetrics(scale: 0.1).scale == HUDMetrics.minimumScale)
    #expect(HUDMetrics(scale: 4).scale == HUDMetrics.maximumScale)
    #expect(HUDMetrics(scale: 0).scale == HUDMetrics.minimumScale)
  }

  @Test func atLeastRaisesASmallerScaleAndLeavesALargerOneAlone() {
    #expect(HUDMetrics(scale: 0.4).atLeast(0.5).scale == 0.5)
    #expect(HUDMetrics(scale: 0.8).atLeast(0.5).scale == 0.8)
    #expect(HUDMetrics(scale: 0.5).atLeast(0.5).scale == 0.5)
  }
}

/// The smallest HUD each display can show. The picked size applies everywhere
/// except where it would leave the shape narrower than the housing it descends
/// from, which reads as a tab floating under the notch.
@Suite("Per-display HUD floor")
struct HUDMinimumScaleTests {
  private func screen(notchWidth: CGFloat?) -> HUDScreenSnapshot {
    let width: CGFloat = 1512
    guard let notchWidth else {
      return HUDScreenSnapshot(
        id: 2,
        frame: CGRect(x: 0, y: 0, width: width, height: 982),
        safeAreaTop: 0,
        auxiliaryTopLeftArea: nil,
        auxiliaryTopRightArea: nil
      )
    }
    let side = (width - notchWidth) / 2
    return HUDScreenSnapshot(
      id: 1,
      frame: CGRect(x: 0, y: 0, width: width, height: 982),
      safeAreaTop: 32,
      auxiliaryTopLeftArea: CGRect(x: 0, y: 0, width: side, height: 32),
      auxiliaryTopRightArea: CGRect(x: width - side, y: 0, width: side, height: 32)
    )
  }

  /// Where a smaller HUD is actually wanted: every point it covers is screen
  /// the user was working in, and there is no housing to stay wider than.
  @Test func aDisplayWithoutANotchKeepsTheGlobalMinimum() {
    #expect(HUDNotchGeometry.minimumScale(for: screen(notchWidth: nil)) == HUDMetrics.minimumScale)
  }

  /// A notch cannot show the smallest sizes, so it floors itself well above
  /// the slider's minimum. The Appearance preview switches to a display
  /// without a notch below this point rather than clamping.
  @Test func aNotchedDisplayFloorsItselfAboveTheSliderMinimum() {
    let floor = HUDNotchGeometry.minimumScale(for: screen(notchWidth: 185))
    #expect(floor > HUDMetrics.minimumScale)
    #expect(HUDMetrics(scale: floor).contentWidth >= 185 + 11 * 2)
  }

  /// A wider housing floors itself higher still.
  @Test func aWiderNotchRaisesTheFloorFurther() {
    let standard = HUDNotchGeometry.minimumScale(for: screen(notchWidth: 185))
    let wide = HUDNotchGeometry.minimumScale(for: screen(notchWidth: 240))
    #expect(wide > standard)
    #expect(HUDMetrics(scale: wide).contentWidth >= 240 + 11 * 2)
  }

  /// Every notch the floor allows leaves the shape wider than its housing, so
  /// the fillets always have bezel to flare into.
  @Test(arguments: [140.0, 160.0, 185.0, 200.0, 220.0, 260.0])
  func theShapeAlwaysCoversItsHousing(notchWidth: Double) {
    let display = screen(notchWidth: notchWidth)
    let floor = HUDNotchGeometry.minimumScale(for: display)
    let shapeWidth = HUDMetrics(scale: floor).contentWidth
    let housing = HUDNotchGeometry.closedSize(for: display).width
    #expect(shapeWidth >= housing + HUDNotchGeometry.filletSize(for: display) * 2)
  }
}
