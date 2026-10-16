import SwiftUI

/// Intelligence's rim: the palette turning around the inside of the shape's
/// open silhouette, a soft band and a crisp line, brighter and wider while the
/// user speaks. The shell clips it to the shape, so only the inner half of
/// each stroke shows and the beam keeps the outside.
///
/// The colors turn by rotating a gradient that is drawn once. Filling a path
/// with a conic gradient every frame rasterizes it on the CPU; a rotation is
/// a transform the render server applies.
struct HUDIntelligenceRimView: View {
  /// Degrees per second the colors travel around the rim.
  static let turnRate = 40.0

  let content: DictationHUDContent
  let palette: HUDGlowPalette
  let metrics: HUDMetrics

  var body: some View {
    let listening = content.showsVoiceVisual
    let alive = content.isAudioAlive
    GeometryReader { proxy in
      TimelineView(.animation(paused: !listening || !alive)) { context in
        let level = alive ? content.audioLevel : 0
        let outline = HUDGlowSilhouetteShape(
          cornerRadius: metrics.bottomCornerRadius,
          inset: 0
        )
        let colors = alive
          ? palette.intelligenceColors
          : [HUDVisualTokens.deadMicAmber]
        let turn = context.date.timeIntervalSinceReferenceDate
          .truncatingRemainder(dividingBy: 360 / Self.turnRate) * Self.turnRate
        let spin = spinningGradient(colors: colors, degrees: turn, in: proxy.size)
        ZStack {
          spin
            .mask(outline.stroke(lineWidth: (12 + 10 * level) * metrics.scale))
            .blur(radius: 7 * metrics.scale)
          spin
            .mask(outline.stroke(lineWidth: 1.6 * metrics.scale))
        }
        .opacity(0.55 + 0.45 * level)
      }
    }
    // Fades with the session like the beam, so the rim drains as the
    // shape retracts rather than vanishing under it.
    .opacity(listening ? 1 : 0)
    .animation(.easeOut(duration: HUDEdgeGlowView.rampDuration), value: listening)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  /// A conic gradient large enough to cover the shape from any angle, turned
  /// about the island's bottom center, where the beam's sweep starts.
  private func spinningGradient(colors: [Color], degrees: Double, in size: CGSize) -> some View {
    let side = 2 * hypot(size.width, size.height)
    return AngularGradient(colors: colors + [colors[0]], center: .center)
      .frame(width: side, height: side)
      .rotationEffect(.degrees(degrees))
      .position(x: size.width / 2, y: size.height)
      .frame(width: size.width, height: size.height)
  }
}

#Preview("Intelligence") {
  HUDShellPreviewHarness(visual: .intelligence)
}
