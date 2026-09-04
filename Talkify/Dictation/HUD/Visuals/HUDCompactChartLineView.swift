import SwiftUI

/// The Waveform + Draft ribbon: Chart Line's conveyor in a 12-point strip
/// at the top of the draft, retuned so the line still reads at the 40%
/// HUD-size floor. The concert Chart Line's 6-point unscaled padding, −10
/// offset, reflection, and 26-point under-glow would clip away in this strip.
struct HUDCompactChartLineView: View {
  let content: DictationHUDContent
  var scale: CGFloat = 1

  @State private var samples: [Float] = []
  @State private var lastTick = Date.distantPast
  @State private var tickInterval: Double = 0.022

  private var live: Bool {
    content.showsVoiceVisual && content.isAudioAlive
  }

  var body: some View {
    TimelineView(.animation(paused: !live)) { context in
      let progress = min(1, max(0, context.date.timeIntervalSince(lastTick) / tickInterval))
      let level = content.audioLevel
      let shape = SmoothLineShape(samples: samples, scrollProgress: live ? progress : 0)
      let hairline = max(1, 1.2 * scale)

      if content.isAudioAlive {
        ZStack {
          shape
            .stroke(
              Self.silver,
              style: StrokeStyle(
                lineWidth: (1.4 + 2 * level) * scale,
                lineCap: .round,
                lineJoin: .round
              )
            )
            .blur(radius: 2 * scale)
            .opacity(0.25 + 0.45 * level)
          shape
            .stroke(
              .white.opacity(0.8 + 0.2 * level),
              style: StrokeStyle(lineWidth: hairline, lineCap: .round, lineJoin: .round)
            )
        }
      } else {
        shape
          .stroke(
            HUDVisualTokens.deadMicAmber.opacity(0.85),
            style: StrokeStyle(lineWidth: hairline, lineCap: .round, lineJoin: .round)
          )
      }
    }
    .padding(.horizontal, 10 * scale)
    .clipped()
    .onAppear { samples = content.levelHistory }
    .onChange(of: content.levelHistory) { _, new in
      let now = Date()
      let gap = now.timeIntervalSince(lastTick)
      if gap < 0.1 {
        tickInterval = tickInterval * 0.8 + gap * 0.2
      }
      samples = new
      lastTick = now
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  /// Same metallic silver as the concert Chart Line, so the ribbon is
  /// recognisably that treatment rather than a second product. Palette
  /// colour stays on the edge beam.
  private static let silver = LinearGradient(
    colors: [
      Color(red: 0.68, green: 0.74, blue: 0.88).opacity(0.85),
      .white,
      Color(red: 0.82, green: 0.86, blue: 0.95),
      .white,
      Color(red: 0.68, green: 0.74, blue: 0.88).opacity(0.85),
    ],
    startPoint: .leading,
    endPoint: .trailing
  )
}
