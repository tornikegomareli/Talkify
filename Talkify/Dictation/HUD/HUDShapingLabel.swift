import SwiftUI

/// The line under everything naming the prompt this session will shape with.
///
/// It sits centered at the bottom of the shape, small and tracked wide, so it
/// reads as a caption on the session rather than as something to look at. A
/// band carrying it at reading size was tried and withdrawn: it took the
/// glance the voice visual and the draft are there for.
///
/// The color comes from the Edge Glow palette and moves with the voice
/// (`ShapingSheen.metal`), which is what makes a static line worth having on
/// screen: it says shaping is armed for as long as the shape is up, and it
/// says it in the palette the user already picked. The arrows change the name
/// in place while it runs.
struct HUDShapingLabel: View {
  let text: String
  let palette: HUDGlowPalette
  let scale: CGFloat
  let level: Double
  let reduceMotion: Bool

  @State private var start = Date()

  /// Deliberately unlike both neighbours: smaller and wider-tracked than the
  /// 15-point draft above it, larger than the 9-point shoulder tags, and
  /// rounded where the draft is not.
  private var font: Font {
    .system(size: 11 * scale, weight: .semibold, design: .rounded)
  }

  var body: some View {
    label
      .frame(maxWidth: .infinity)
      .allowsHitTesting(false)
  }

  @ViewBuilder
  private var label: some View {
    if reduceMotion {
      // Nothing travels and nothing breathes: one palette color, held still.
      Text(text)
        .font(font)
        .tracking(1.4 * scale)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .foregroundStyle(Color(palette.statusAccent).opacity(0.85))
    } else {
      TimelineView(.animation) { context in
        Text(text)
          .font(font)
          .tracking(1.4 * scale)
          .lineLimit(1)
          .minimumScaleFactor(0.6)
          // White going in: the shader keeps the glyph coverage and throws
          // the color away, so the palette decides what comes out.
          .foregroundStyle(.white)
          .layerEffect(
            ShaderLibrary.shapingSheen(
              .float2(size),
              .float(Float(context.date.timeIntervalSince(start))),
              .float(Float(min(max(level, 0), 1))),
              .color(palette.sheenColors.0),
              .color(palette.sheenColors.1),
              .color(palette.sheenColors.2)
            ),
            maxSampleOffset: .zero
          )
      }
      .onGeometryChange(for: CGSize.self, of: \.size) { size = $0 }
    }
  }

  @State private var size: CGSize = .zero
}
