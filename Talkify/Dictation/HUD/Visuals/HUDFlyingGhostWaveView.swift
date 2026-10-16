import SwiftUI

/// Flying Ghost's voice indicator: four capsules in the palette at the stage's
/// trailing edge, reaching higher the louder the voice. Silence leaves them
/// resting low rather than flat, and a dead microphone stops them in amber.
struct HUDFlyingGhostWaveView: View {
  static let barCount = 4
  /// The indicator's full height at full HUD size.
  static let height: CGFloat = 18
  static let barWidth: CGFloat = 3
  static let barSpacing: CGFloat = 2.5
  /// The indicator's width at full HUD size.
  static let width = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barSpacing

  let content: DictationHUDContent
  let palette: HUDGlowPalette
  let scale: CGFloat

  var body: some View {
    let alive = content.isAudioAlive
    let listening = content.showsVoiceVisual
    TimelineView(.animation(minimumInterval: 1 / 30, paused: !listening || !alive)) { context in
      let t = context.date.timeIntervalSinceReferenceDate
      let level = alive ? content.audioLevel : 0
      let colors = alive ? palette.ghostColors : [HUDVisualTokens.deadMicAmber]
      HStack(spacing: Self.barSpacing * scale) {
        ForEach(0..<Self.barCount, id: \.self) { bar in
          Capsule()
            .fill(LinearGradient(colors: colors, startPoint: .bottom, endPoint: .top))
            .frame(width: Self.barWidth * scale, height: Self.reach(bar: bar, at: t, level: level) * Self.height * scale)
        }
      }
      .frame(height: Self.height * scale)
    }
    .accessibilityHidden(true)
  }

  /// A bar's share of the indicator's height. Each bar runs at its own rate so
  /// the four never pulse in step; the voice decides how far they reach.
  static func reach(bar: Int, at t: TimeInterval, level: Double) -> Double {
    let wave = abs(sin(t * (2.6 + Double(bar) * 0.85) + Double(bar) * 1.9))
    return restingReach + (1 - restingReach) * min(1, level * 1.4) * (0.35 + 0.65 * wave)
  }

  /// Where the bars rest in silence.
  static let restingReach = 0.35
}
