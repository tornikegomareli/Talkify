import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import Talkify

/// Flying Ghost's pure rules: how wide the island is before and after the
/// first word, how high its voice indicator reaches, and when the ghost blinks.
struct HUDFlyingGhostTests {
  private let notched = HUDPreviewScreen.notched
  private let external = HUDPreviewScreen.external

  @Test func theIslandListensNarrowAndWidensForTheFirstWord() {
    let metrics = HUDMetrics.standard
    let full = metrics.contentWidth
    let listening = DictationHUDShellView.flyingGhostWidth(
      expanded: false, fullWidth: full, screen: notched, metrics: metrics)
    let speaking = DictationHUDShellView.flyingGhostWidth(
      expanded: true, fullWidth: full, screen: notched, metrics: metrics)

    #expect(listening < speaking)
    #expect(speaking == full)
  }

  /// A small HUD must not listen narrower than the housing it grows from,
  /// or it reads as a tab under the notch.
  @Test func theListeningIslandNeverNarrowsPastTheHousing() {
    let metrics = HUDMetrics(scale: 0.4)
    let width = DictationHUDShellView.flyingGhostWidth(
      expanded: false, fullWidth: metrics.contentWidth, screen: notched, metrics: metrics)

    #expect(width >= HUDNotchGeometry.minimumShapeWidth(for: notched))
    #expect(width <= metrics.contentWidth)
  }

  @Test func aSimulatedNotchListensAtTheScaledWidth() {
    let metrics = HUDMetrics.standard
    let width = DictationHUDShellView.flyingGhostWidth(
      expanded: false, fullWidth: metrics.contentWidth, screen: external, metrics: metrics)

    #expect(width == DictationHUDShellView.flyingGhostListeningWidth)
  }

  /// Silence leaves the bars resting low, never flat, and no voice drives
  /// them past their full height.
  @Test func theVoiceIndicatorRestsInSilenceAndStaysInBounds() {
    for bar in 0..<HUDFlyingGhostWaveView.barCount {
      for t in stride(from: 0.0, to: 4.0, by: 0.05) {
        #expect(HUDFlyingGhostWaveView.reach(bar: bar, at: t, level: 0)
          == HUDFlyingGhostWaveView.restingReach)
        let loud = HUDFlyingGhostWaveView.reach(bar: bar, at: t, level: 1)
        #expect(loud >= HUDFlyingGhostWaveView.restingReach)
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

  /// The ghost's arc starts under the camera and ends on its resting place
  /// exactly, sets off and lands upright, and leans left on the way, because
  /// the corner is to the left.
  @Test func theGhostFliesAnArcFromTheCameraToTheCorner() {
    let start = CGPoint(x: 270, y: 28)
    let end = CGPoint(x: 30, y: 59)
    let launch = HUDFlyingGhostView.flight(progress: 0, from: start, to: end, scale: 1)
    let landing = HUDFlyingGhostView.flight(progress: 1, from: start, to: end, scale: 1)
    #expect(launch.point == start && abs(launch.lean) < 0.001)
    #expect(landing.point == end && abs(landing.lean) < 0.001)
    let midway = HUDFlyingGhostView.flight(progress: 0.5, from: start, to: end, scale: 1)
    #expect(midway.lean < 0)
    #expect(midway.point.y > end.y)
  }

  /// The mouth only opens for a bite, and is widest halfway through it.
  @Test func aBiteOpensTheMouthOnceAndClosesIt() {
    let duration = HUDGhostView.chompDuration
    #expect(HUDGhostView.chomp(at: -0.1) == 0)
    #expect(HUDGhostView.chomp(at: duration / 2) > 0.99)
    #expect(HUDGhostView.chomp(at: duration) == 0)
  }

  /// Speech ending is when Flying Ghost's ghost flies home, so the content
  /// says so, and the next session starts without it.
  @MainActor
  @Test func finalizingIsMarkedAndTheNextSessionClearsIt() {
    let store = AppSettings.previewStore()
    store.voiceVisual = .flyingGhost
    let stage = HUDStage(settings: store)
    let hud = DictationHUDController(stage: stage, settings: store)
    hud.showListening(on: nil, isLatched: false, settings: store.sessionSettings)
    #expect(!stage.dictationContent.isFinalizing)
    hud.showFinalizing()
    #expect(stage.dictationContent.isFinalizing)
    hud.showListening(on: nil, isLatched: false, settings: store.sessionSettings)
    #expect(!stage.dictationContent.isFinalizing)
  }

  /// Every palette gives the ghost the same kind of color set: five colors
  /// with a real spread of lightness, so the mesh moves visibly and the effect
  /// looks the same whichever palette is picked.
  @Test(arguments: HUDGlowPalette.allCases)
  func everyPaletteGivesTheGhostTheSameKindOfColors(palette: HUDGlowPalette) {
    let lightness = palette.ghostColors.map { color in
      let resolved = color.resolve(in: EnvironmentValues())
      return 0.2126 * Double(resolved.red) + 0.7152 * Double(resolved.green) + 0.0722 * Double(resolved.blue)
    }
    #expect(lightness.count == 5)
    #expect(lightness.max()! - lightness.min()! > 0.2)
  }

  /// The glow is balanced by lightness: the reference palette is unscaled,
  /// a lighter palette is always dimmed more than a deeper one, and no
  /// palette leaves the bounds.
  @Test func lighterPalettesGlowLessSoAllReadTheSame() {
    #expect(abs(HUDGlowPalette.intelligence.ghostGlowBalance - 1) < 0.0001)
    let byLightness = HUDGlowPalette.allCases.sorted {
      HUDGlowPalette.averageLightness(of: $0.ghostColors) < HUDGlowPalette.averageLightness(of: $1.ghostColors)
    }
    for (deeper, lighter) in zip(byLightness, byLightness.dropFirst()) {
      #expect(deeper.ghostGlowBalance >= lighter.ghostGlowBalance)
    }
    for palette in HUDGlowPalette.allCases {
      #expect(HUDGlowPalette.ghostGlowBalanceRange.contains(palette.ghostGlowBalance))
    }
  }

  @Test func theGhostBlinksBrieflyAndOtherwiseKeepsItsEyesOpen() {
    let period = HUDGhostView.blinkPeriod
    let blink = HUDGhostView.blinkDuration
    #expect(HUDGhostView.openness(at: period + blink / 2) < 0.2)
    #expect(HUDGhostView.openness(at: period + blink * 2) == 1)
    #expect(HUDGhostView.openness(at: period / 2) == 1)
  }
}
