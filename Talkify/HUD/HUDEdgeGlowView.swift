import SwiftUI

/// The Edge Glow beam, built the way the article's gist builds it: the open
/// silhouette (down the left flank, across the bottom, up the right flank —
/// never the hidden top edge) is stroked with an angular palette gradient
/// three times — a crisp line and two blurred copies — and the shader
/// (EdgeGlow.metal) masks that picture by distance from the origin.
///
/// The article moves the origin with the user's finger; the HUD has no
/// finger, so the origin sweeps the silhouette instead — corner to notch and
/// back, eased at the turnarounds — starting from under the housing at each
/// session start. The mask blooms in on session start, breathes with the
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
    /// Stroke width: crisp line at half this, blurred copies at full. The
    /// gist uses 4 on a 240pt capsule; our shape is wider and the mask eats
    /// brightness, so the strokes need more body to read as a beam.
    nonisolated static let lineWidth: Double = 6
    /// Blur of the outer halo stroke (the inner copy runs at half).
    nonisolated static let blurRadius: Double = 12
    /// Seconds for one end-to-end sweep of the silhouette.
    nonisolated static let sweepDuration: TimeInterval = 4.0

    let content: DictationHUDContent
    let settings: AppSettings

    /// Reset on every session start so the sweep begins at bottom-center,
    /// directly under the housing.
    @State private var sweepStart = Date()

    var body: some View {
        GeometryReader { proxy in
            let listening = content.showsVoiceVisual
            TimelineView(.animation(paused: !listening)) { context in
                // Plain values for the @Sendable keyframeAnimator content
                // closure; the body re-evaluates on every level tick and
                // timeline frame, so they stay fresh.
                let size = proxy.size
                let alive = content.isAudioAlive
                let level = content.audioLevel
                // Glow Lab (prototype): the voice mappings under test, each
                // behind its Settings toggle. Delete with the lab (#12).
                // Resting brightness stays near the gist's constant 3.0 so
                // the halo never starves; the voice adds the flare on top.
                let amplitude = alive
                    ? (settings.glowVoiceBrightness ? 1.8 + 1.2 * level : 2.4)
                    : 1.5
                let lineWidth = settings.glowVoiceThickness
                    ? Self.lineWidth * (1 + level)
                    : Self.lineWidth
                let blurRadius = settings.glowVoiceThickness
                    ? Self.blurRadius * (1 + 0.5 * level)
                    : Self.blurRadius
                let reach = settings.glowVoiceReach ? 0.7 + 1.1 * level : 1.0
                let origin = Self.sweepOrigin(
                    at: context.date.timeIntervalSince(sweepStart),
                    in: size
                )
                HUDGlowSilhouetteShape(
                    cornerRadius: HUDNotchGeometry.bottomCornerRadius,
                    inset: Self.spill
                )
                .glow(
                    fill: alive ? settings.glowPalette.stroke : AnyShapeStyle(.amber),
                    lineWidth: lineWidth,
                    blurRadius: blurRadius
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
                            .float(progress),
                            .float(reach)
                        ),
                        isEnabled: progress > 0 || listening
                    )
                } keyframes: { _ in
                    // No MoveKeyframe: the track starts from the current
                    // value, so a session ending mid-bloom reverses smoothly.
                    if listening {
                        LinearKeyframe(1.0, duration: Self.rampDuration)
                    } else {
                        LinearKeyframe(0.0, duration: Self.rampDuration)
                    }
                }
            }
        }
        .padding(.horizontal, -Self.spill)
        .padding(.bottom, -Self.spill)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: content.sessionEpoch) {
            sweepStart = .now
        }
    }

    /// The eased ping-pong position along the silhouette at time `t` (left
    /// tip → bottom → right tip → back), phase-shifted so t = 0 lands at
    /// bottom-center. Shared with the particle cloud so the motes chase the
    /// same point the beam highlights.
    nonisolated static func sweepFraction(at t: TimeInterval) -> Double {
        let phase = ((t / sweepDuration) + 0.5)
            .truncatingRemainder(dividingBy: 2.0)
        let linear = phase < 1.0 ? phase : 2.0 - phase
        return linear * linear * (3.0 - 2.0 * linear)
    }

    /// Where the mask origin sits at time `t`, in this view's coordinates.
    nonisolated private static func sweepOrigin(
        at t: TimeInterval,
        in size: CGSize
    ) -> CGPoint {
        HUDGlowSilhouetteShape.point(
            atArcFraction: sweepFraction(at: t),
            cornerRadius: HUDNotchGeometry.bottomCornerRadius,
            inset: spill,
            in: size
        )
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

    /// The point at `fraction` (0…1) of the silhouette's arc length, from the
    /// left flank's tip to the right flank's tip. Mirrors `path(in:)`.
    nonisolated static func point(
        atArcFraction fraction: Double,
        cornerRadius: CGFloat,
        inset: CGFloat,
        in size: CGSize
    ) -> CGPoint {
        let left = inset
        let right = size.width - inset
        let bottom = size.height - inset
        let radius = min(cornerRadius, bottom / 2)

        let flank = bottom - radius
        let corner = Double.pi * radius / 2
        let run = (right - left) - 2 * radius
        let total = 2 * flank + 2 * corner + run
        let distance = fraction.clamped(to: 0...1) * total

        if distance < flank {
            return CGPoint(x: left, y: distance)
        }
        if distance < flank + corner {
            let angle = Double.pi - (distance - flank) / radius
            return CGPoint(
                x: left + radius + radius * cos(angle),
                y: bottom - radius + radius * sin(angle)
            )
        }
        if distance < flank + corner + run {
            return CGPoint(x: left + radius + (distance - flank - corner), y: bottom)
        }
        if distance < flank + 2 * corner + run {
            let angle = Double.pi / 2 - (distance - flank - corner - run) / radius
            return CGPoint(
                x: right - radius + radius * cos(angle),
                y: bottom - radius + radius * sin(angle)
            )
        }
        return CGPoint(x: right, y: flank - (distance - flank - 2 * corner - run))
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
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
