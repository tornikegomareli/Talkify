import SwiftUI

/// The HUD's visible silhouette as one open path: from the top-left where the
/// shape meets the screen edge, down the left flank, across the bottom, and
/// up to the top-right. Deliberately not a closed loop — a closed border
/// would run the glow along the top edge, which sits against the screen and
/// reads as a ring around a pillar.
struct HUDEdgePath: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        let r = min(HUDNotchGeometry.bottomCornerRadius, rect.height / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r))
        p.addArc(
            center: CGPoint(x: rect.minX + r, y: rect.maxY - r),
            radius: r,
            startAngle: .degrees(180),
            endAngle: .degrees(90),
            clockwise: true
        )
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.maxY))
        p.addArc(
            center: CGPoint(x: rect.maxX - r, y: rect.maxY - r),
            radius: r,
            startAngle: .degrees(90),
            endAngle: .degrees(0),
            clockwise: true
        )
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return p
    }
}

/// The edge-glow voice visual: a white/silver comet sweeping back and forth
/// along the silhouette — corner to notch and back — over a faint resting
/// outline. Voice level drives brightness. A dead microphone freezes the
/// comet and turns the outline amber.
struct HUDEdgeGlowView: View {
    /// Seconds for one full sweep (one direction).
    static let sweepPeriod: Double = 2.2
    /// Fraction of the path the comet covers.
    static let cometLength: Double = 0.30

    let content: DictationHUDContent

    @State private var start = Date()

    var body: some View {
        TimelineView(.animation) { context in
            let level = content.audioLevel
            let brightness = 0.35 + 0.65 * level

            if content.isAudioAlive {
                let t = context.date.timeIntervalSince(start) / Self.sweepPeriod
                // Ping-pong: sweeps to the other corner, then back.
                let phase = t.truncatingRemainder(dividingBy: 2)
                let pos = phase < 1 ? phase : 2 - phase
                let from = max(0, pos - Self.cometLength / 2)
                let to = min(1, pos + Self.cometLength / 2)

                ZStack {
                    // Resting outline so silence still shows a live edge.
                    HUDEdgePath()
                        .stroke(.white.opacity(0.08 + 0.10 * level), lineWidth: 1)

                    // The comet: wide faint halo, medium bloom, bright core.
                    comet(from: from, to: to, width: 7, blur: 6, opacity: 0.35 * brightness)
                    comet(from: from, to: to, width: 3.5, blur: 2.5, opacity: 0.7 * brightness)
                    comet(from: from, to: to, width: 1.6, blur: 0.4, opacity: brightness)
                }
            } else {
                // Dead microphone: static dim amber outline, no motion.
                HUDEdgePath()
                    .stroke(Color.orange.opacity(0.5), lineWidth: 1.5)
                    .blur(radius: 0.5)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func comet(
        from: Double,
        to: Double,
        width: CGFloat,
        blur: CGFloat,
        opacity: Double
    ) -> some View {
        HUDEdgePath()
            .trim(from: from, to: to)
            .stroke(
                .white.opacity(opacity),
                style: StrokeStyle(lineWidth: width, lineCap: .round)
            )
            .blur(radius: blur)
    }
}

#Preview("Edge glow · live") {
    HUDShellPreviewHarness(visual: .glow)
}

#Preview("Edge glow · dead mic") {
    HUDShellPreviewHarness(visual: .glow, micAlive: false)
}
