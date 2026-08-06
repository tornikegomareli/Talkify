import SwiftUI

/// The Edge Glow beam, built the way the article's gist builds it: the open
/// silhouette (down the left flank, across the bottom, up the right flank —
/// never the hidden top edge) is stroked with an angular palette gradient
/// three times — a crisp line and two blurred copies — and the shader
/// (EdgeGlow.metal) masks that picture by distance from the origin. The mask
/// blooms out of the notch housing on session start, breathes with the
/// microphone level, and drains back when the session ends. A dead microphone
/// swaps the palette for a motionless amber (CONTEXT.md: dead ≠ silent).
///
/// The view stays mounted while the glow variant is selected — the session
/// ramp must keep rendering after `showsVoiceVisual` flips false or the
/// drain-out never plays; the shader is disabled once the ramp reaches zero.
struct HUDEdgeGlowView: View {
    /// Room the blurred strokes get beyond the shape's border.
    nonisolated static let spill: CGFloat = 28
    /// Duration of the bloom-in and drain-out ramps.
    nonisolated static let rampDuration: TimeInterval = 0.4
    /// The gist's stroke width: crisp line at half this, blurs at full.
    nonisolated static let lineWidth: Double = 4

    let content: DictationHUDContent
    /// Height of the notch housing band; the glow origin sits at its
    /// bottom-center, where the light story starts.
    let housingHeight: CGFloat

    var body: some View {
        GeometryReader { proxy in
            // Plain values for the @Sendable keyframeAnimator content closure;
            // the body re-evaluates on every level tick, so they stay fresh.
            let size = proxy.size
            let origin = CGPoint(x: size.width / 2, y: housingHeight)
            let listening = content.showsVoiceVisual
            let alive = content.isAudioAlive
            let amplitude = alive ? 0.6 + 2.4 * content.audioLevel : 1.5
            HUDGlowSilhouetteShape(
                cornerRadius: HUDNotchGeometry.bottomCornerRadius,
                inset: Self.spill
            )
            .glow(
                fill: alive ? AnyShapeStyle(.palette) : AnyShapeStyle(.amber),
                lineWidth: Self.lineWidth
            )
            .keyframeAnimator(
                initialValue: 0.0,
                trigger: listening
            ) { view, progress in
                view.colorEffect(
                    ShaderLibrary.edgeGlow(
                        .float2(origin),
                        .float2(size),
                        .float(amplitude),
                        .float(progress)
                    ),
                    isEnabled: progress > 0 || listening
                )
            } keyframes: { _ in
                // No MoveKeyframe: the track starts from the current value,
                // so a session ending mid-bloom reverses smoothly.
                if listening {
                    LinearKeyframe(1.0, duration: Self.rampDuration)
                } else {
                    LinearKeyframe(0.0, duration: Self.rampDuration)
                }
            }
        }
        .padding(.horizontal, -Self.spill)
        .padding(.bottom, -Self.spill)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The HUD's open silhouette as a strokable path: left flank, bottom run with
/// its two corner arcs, right flank. The top edge is the screen edge and is
/// never drawn.
struct HUDGlowSilhouetteShape: Shape {
    var cornerRadius: CGFloat
    /// Distance from the view's left/right/bottom edges to the silhouette
    /// (the spill the blurred strokes need).
    var inset: CGFloat

    nonisolated func path(in rect: CGRect) -> Path {
        let left = rect.minX + inset
        let right = rect.maxX - inset
        let bottom = rect.maxY - inset
        let radius = min(cornerRadius, (bottom - rect.minY) / 2)

        var path = Path()
        path.move(to: CGPoint(x: left, y: rect.minY))
        path.addLine(to: CGPoint(x: left, y: bottom - radius))
        path.addArc(
            tangent1End: CGPoint(x: left, y: bottom),
            tangent2End: CGPoint(x: left + radius, y: bottom),
            radius: radius
        )
        path.addLine(to: CGPoint(x: right - radius, y: bottom))
        path.addArc(
            tangent1End: CGPoint(x: right, y: bottom),
            tangent2End: CGPoint(x: right, y: bottom - radius),
            radius: radius
        )
        path.addLine(to: CGPoint(x: right, y: rect.minY))
        return path
    }
}

// The gist's GlowModifier, verbatim: a crisp stroke plus two blurred copies.
private extension Shape {
    func glow(
        fill: some ShapeStyle,
        lineWidth: Double,
        blurRadius: Double = 8.0,
        lineCap: CGLineCap = .round
    ) -> some View {
        stroke(style: StrokeStyle(lineWidth: lineWidth / 2, lineCap: lineCap))
            .fill(fill)
            .overlay {
                stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: lineCap))
                    .fill(fill)
                    .blur(radius: blurRadius)
            }
            .overlay {
                stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: lineCap))
                    .fill(fill)
                    .blur(radius: blurRadius / 2)
            }
    }
}

private extension ShapeStyle where Self == AngularGradient {
    /// The gist's palette.
    static var palette: AngularGradient {
        .angularGradient(
            stops: [
                .init(color: .blue, location: 0.0),
                .init(color: .purple, location: 0.2),
                .init(color: .red, location: 0.4),
                .init(color: .mint, location: 0.5),
                .init(color: .indigo, location: 0.7),
                .init(color: .pink, location: 0.9),
                .init(color: .blue, location: 1.0),
            ],
            center: .center,
            startAngle: Angle(radians: .zero),
            endAngle: Angle(radians: .pi * 2)
        )
    }
}

private extension ShapeStyle where Self == Color {
    /// The dead-microphone state: motionless amber.
    static var amber: Color {
        Color(red: 1.0, green: 0.6, blue: 0.16)
    }
}

#Preview("Edge glow · live") {
    HUDShellPreviewHarness(visual: .glow)
}

#Preview("Edge glow · session cycle") {
    HUDShellPreviewHarness(visual: .glow, simulatesSessionCycle: true)
}

#Preview("Edge glow · dead mic") {
    HUDShellPreviewHarness(visual: .glow, micAlive: false)
}
