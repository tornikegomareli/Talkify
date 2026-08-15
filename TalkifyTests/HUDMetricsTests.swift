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
}
