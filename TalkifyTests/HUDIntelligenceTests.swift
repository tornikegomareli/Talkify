import CoreGraphics
import Testing
@testable import Talkify

/// Intelligence's pure rules: how wide the island is before and after the
/// first word, how high its voice indicator reaches, and when the ghost blinks.
struct HUDIntelligenceTests {
  private let notched = HUDPreviewScreen.notched
  private let external = HUDPreviewScreen.external

  @Test func theIslandListensNarrowAndWidensForTheFirstWord() {
    let metrics = HUDMetrics.standard
    let full = metrics.contentWidth
    let listening = DictationHUDShellView.intelligenceWidth(
      expanded: false, fullWidth: full, screen: notched, metrics: metrics)
    let speaking = DictationHUDShellView.intelligenceWidth(
      expanded: true, fullWidth: full, screen: notched, metrics: metrics)

    #expect(listening < speaking)
    #expect(speaking == full)
  }

  /// A small HUD must not listen narrower than the housing it grows from,
  /// or it reads as a tab under the notch.
  @Test func theListeningIslandNeverNarrowsPastTheHousing() {
    let metrics = HUDMetrics(scale: 0.4)
    let width = DictationHUDShellView.intelligenceWidth(
      expanded: false, fullWidth: metrics.contentWidth, screen: notched, metrics: metrics)

    #expect(width >= HUDNotchGeometry.minimumShapeWidth(for: notched))
    #expect(width <= metrics.contentWidth)
  }

  @Test func aSimulatedNotchListensAtTheScaledWidth() {
    let metrics = HUDMetrics.standard
    let width = DictationHUDShellView.intelligenceWidth(
      expanded: false, fullWidth: metrics.contentWidth, screen: external, metrics: metrics)

    #expect(width == DictationHUDShellView.intelligenceListeningWidth)
  }

  /// Silence leaves the bars resting low, never flat, and no voice drives
  /// them past their full height.
  @Test func theVoiceIndicatorRestsInSilenceAndStaysInBounds() {
    for bar in 0..<HUDIntelligenceWaveView.barCount {
      for t in stride(from: 0.0, to: 4.0, by: 0.05) {
        #expect(HUDIntelligenceWaveView.reach(bar: bar, at: t, level: 0)
          == HUDIntelligenceWaveView.restingReach)
        let loud = HUDIntelligenceWaveView.reach(bar: bar, at: t, level: 1)
        #expect(loud >= HUDIntelligenceWaveView.restingReach)
        #expect(loud <= 1)
      }
    }
  }

  @Test func theGhostBlinksBrieflyAndOtherwiseKeepsItsEyesOpen() {
    let period = HUDIntelligenceGhostView.blinkPeriod
    let blink = HUDIntelligenceGhostView.blinkDuration
    #expect(HUDIntelligenceGhostView.openness(at: period + blink / 2) < 0.2)
    #expect(HUDIntelligenceGhostView.openness(at: period + blink * 2) == 1)
    #expect(HUDIntelligenceGhostView.openness(at: period / 2) == 1)
  }
}
