import CoreGraphics
import Foundation
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

  /// The flight stays a hover around the ghost's place, and the voice widens
  /// it rather than moving the ghost somewhere else.
  @Test func theGhostsFlightStaysCloseAndWidensWithTheVoice() {
    var quietReach = 0.0
    var loudReach = 0.0
    for step in 0..<400 {
      let phase = Double(step) * 0.05
      let quiet = HUDGhostPose.at(phase: phase, energy: 0)
      let loud = HUDGhostPose.at(phase: phase, energy: 1)
      #expect(abs(loud.x) <= 0.16 && abs(loud.y) <= 0.115)
      #expect(abs(loud.tilt) <= 10)
      #expect(loud.stretch > 0.9 && loud.stretch < 1.1)
      quietReach = max(quietReach, abs(quiet.x))
      loudReach = max(loudReach, abs(loud.x))
    }
    #expect(loudReach > quietReach)
  }

  /// The ghost leans the way it is moving sideways.
  @Test func theGhostLeansIntoItsMotion() {
    let before = HUDGhostPose.at(phase: 0.1, energy: 0.5)
    let after = HUDGhostPose.at(phase: 0.11, energy: 0.5)
    #expect((after.x - before.x) * before.tilt > 0)
  }

  /// Energy follows the voice over a fraction of a second, so a burst eases
  /// the flight up instead of snapping it, and a long gap resumes in place.
  @MainActor
  @Test func theFlightEasesTowardTheVoiceAndResumesInPlace() {
    let flight = HUDGhostFlight()
    let start = Date(timeIntervalSinceReferenceDate: 0)
    flight.advance(to: start, level: 1)
    flight.advance(to: start.addingTimeInterval(0.05), level: 1)
    #expect(flight.energy > 0 && flight.energy < 0.5)
    for frame in 2...60 {
      flight.advance(to: start.addingTimeInterval(Double(frame) * 0.05), level: 1)
    }
    #expect(flight.energy > 0.9)
    let phase = flight.phase
    flight.advance(to: start.addingTimeInterval(100), level: 1)
    #expect(flight.phase - phase < 0.3)
  }

  @Test func theGhostBlinksBrieflyAndOtherwiseKeepsItsEyesOpen() {
    let period = HUDIntelligenceGhostView.blinkPeriod
    let blink = HUDIntelligenceGhostView.blinkDuration
    #expect(HUDIntelligenceGhostView.openness(at: period + blink / 2) < 0.2)
    #expect(HUDIntelligenceGhostView.openness(at: period + blink * 2) == 1)
    #expect(HUDIntelligenceGhostView.openness(at: period / 2) == 1)
  }
}
