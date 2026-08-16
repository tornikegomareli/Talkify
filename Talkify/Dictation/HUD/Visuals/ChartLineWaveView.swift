import SwiftUI

/// The Chart Line look rendered as a conveyor instead of a chart: each level
/// tick shifts the buffer one slot, so the shape interpolates the scroll
/// offset against the tick clock and the points glide left continuously —
/// no per-tick jump, no Swift Charts re-render.
///
/// The treatment is its own: a crisp core over two glow passes (wide soft
/// halo, tight bloom) so the line stays sharp instead of blurry, a
/// cyan→violet→magenta gradient whose hues drift continuously, and the
/// voice driving stroke weight, glow reach, and brightness.
struct ChartLineWaveView: View {
  let content: DictationHUDContent

  @State private var samples: [Float] = []
  @State private var lastTick = Date.distantPast
  /// Measured time between level ticks, smoothed; scroll speed follows it.
  @State private var tickInterval: Double = 0.022

  var body: some View {
    TimelineView(.animation) { context in
      let progress = min(1, max(0, context.date.timeIntervalSince(lastTick) / tickInterval))
      let level = content.audioLevel
      let shape = SmoothLineShape(samples: samples, scrollProgress: progress)

      if content.isAudioAlive {
        ZStack {
          // Ambient under-glow: a wide soft pool of light beneath
          // the line, breathing with the voice.
          Ellipse()
            .fill(Self.silver)
            .frame(height: 26)
            .padding(.horizontal, 60)
            .blur(radius: 22)
            .opacity(0.08 + 0.22 * level)

          // Glass-floor reflection: the wave mirrored about its
          // rest line, soft and fading downward.
          shape
            .stroke(
              Self.silver,
              style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
            )
            .scaleEffect(y: -1)
            .blur(radius: 2.5)
            .opacity(0.16 + 0.22 * level)
            .mask(
              LinearGradient(
                colors: [.clear, .white.opacity(0.8), .clear],
                startPoint: .top,
                endPoint: .bottom
              )
            )

          // Wide halo: breathes with the voice. Cool silver, so the
          // bloom reads as light on glass rather than color.
          shape
            .stroke(
              Self.silver,
              style: StrokeStyle(
                lineWidth: 4 + 8 * level,
                lineCap: .round,
                lineJoin: .round
              )
            )
            .blur(radius: 9)
            .opacity(0.2 + 0.6 * level)
          // Tight bloom hugging the core.
          shape
            .stroke(
              Self.silver,
              style: StrokeStyle(
                lineWidth: 2.5 + 3 * level,
                lineCap: .round,
                lineJoin: .round
              )
            )
            .blur(radius: 2.5)
            .opacity(0.8)
          // Crisp white-hot core — never blurred.
          shape
            .stroke(
              .white.opacity(0.75 + 0.25 * level),
              style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round)
            )
          // Metallic specular: a soft band of extra light sweeping
          // along the line, the classic glass/metal sheen.
          shape
            .stroke(
              .white,
              style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round)
            )
            .blur(radius: 0.8)
            .mask(specularBand(at: context.date))
        }
        // Lift the rest line toward the shape's visual center (the
        // housing strip above makes the band's own middle read low).
        .offset(y: -10)
      } else {
        shape
          .stroke(
            Color.orange.opacity(0.55),
            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
          )
          .offset(y: -10)
      }
    }
    .clipped()
    .onChange(of: content.levelHistory) { _, new in
      let now = Date()
      let gap = now.timeIntervalSince(lastTick)
      if gap < 0.1 {
        tickInterval = tickInterval * 0.8 + gap * 0.2
      }
      samples = new
      lastTick = now
    }
  }

  /// Metallic silver: white body cooling into a faint blue-gray at the
  /// ends — the edge glow's palette, no saturated hues.
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

  /// A soft bright band ping-ponging across the strip; masking the extra
  /// specular stroke with it makes the light travel along the line.
  private func specularBand(at date: Date) -> some View {
    GeometryReader { proxy in
      let phase = date.timeIntervalSinceReferenceDate
        .truncatingRemainder(dividingBy: 1000) / 3.2
      let cycle = phase.truncatingRemainder(dividingBy: 2)
      let lin = cycle < 1 ? cycle : 2 - cycle
      let eased = lin * lin * (3 - 2 * lin)
      let bandWidth = proxy.size.width * 0.3

      LinearGradient(
        colors: [.clear, .white, .clear],
        startPoint: .leading,
        endPoint: .trailing
      )
      .frame(width: bandWidth)
      .offset(x: eased * (proxy.size.width + bandWidth) - bandWidth)
    }
  }
}
