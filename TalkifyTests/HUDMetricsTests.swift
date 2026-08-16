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

  /// Compact is the only visual built around the live draft, so it is the only
  /// one that gives up the smallest sizes. Reduce Motion restores the draft for
  /// every visual and takes them away from all three.
  @Test func onlyCompactAndReduceMotionGiveUpTheSmallestSizes() {
    #expect(HUDMetrics.minimumScale(for: .compact, reduceMotion: false) == 0.4)
    #expect(HUDMetrics.minimumScale(for: .waveform, reduceMotion: false) == 0.2)
    #expect(HUDMetrics.minimumScale(for: .glow, reduceMotion: false) == 0.2)
    #expect(HUDMetrics.minimumScale(for: .waveform, reduceMotion: true) == 0.4)
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

  /// The widths a real notch reports across the scaled display modes a MacBook
  /// offers. Every one of them has to leave the shape wider than its housing,
  /// so the fillets always have bezel to flare into, and every one of them has
  /// to sit above the slider's own minimum — which is what makes this a
  /// per-display measurement rather than a constant.
  @Test(arguments: [155.0, 185.0, 207.0, 244.0, 273.0])
  func everyRealNotchCoversItsHousingAndRaisesTheFloor(notchWidth: Double) {
    let display = screen(notchWidth: notchWidth)
    let floor = HUDNotchGeometry.minimumScale(for: display)
    let shapeWidth = HUDMetrics(scale: floor).contentWidth
    let housing = HUDNotchGeometry.closedSize(for: display).width

    #expect(shapeWidth >= housing + HUDNotchGeometry.filletSize(for: display) * 2)
    #expect(floor > HUDMetrics.minimumScale)
  }
}

/// The two floors resolve together, and the higher one wins.
@MainActor
@Suite("Combined HUD floors")
struct HUDShellMetricsTests {
  private let external = HUDPreviewScreen.external

  private func scale(picked: Double, visual: HUDVoiceVisualStyle) -> CGFloat {
    DictationHUDShellView.metrics(
      picked: HUDMetrics(scale: picked),
      screen: external,
      visual: visual,
      reduceMotion: false
    ).scale
  }

  @Test func aDraftLayoutIsHeldAtTheReadableFloorAndOthersAreNot() {
    #expect(scale(picked: 0.2, visual: .compact) == HUDMetrics.minimumReadableScale)
    #expect(scale(picked: 0.2, visual: .waveform) == HUDMetrics.minimumScale)
    #expect(scale(picked: 0.7, visual: .compact) == 0.7)
  }

  /// A notched display floors above the readable floor at most scaled modes, so
  /// the display is usually the one deciding.
  @Test func theHigherFloorWins() {
    let notched = HUDPreviewScreen.notched
    let scale = DictationHUDShellView.metrics(
      picked: HUDMetrics(scale: HUDMetrics.minimumScale),
      screen: notched,
      visual: .waveform,
      reduceMotion: false
    ).scale
    #expect(scale == HUDNotchGeometry.minimumScale(for: notched))
    #expect(scale > HUDMetrics.minimumScale)
  }
}
