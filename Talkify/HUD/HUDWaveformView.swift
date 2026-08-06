import Charts
import SwiftUI

/// The waveform looks under audition, each mimicking a reference
/// implementation, all fed by the same live level history:
/// - Article: "Writing a High-Performance Audio Wave in SwiftUI" — flat
///   sharp rects, linear heights, warm amber.
/// - Silver: our styling of the same bar architecture.
/// - Capsules / Chart Line / Chart Area: jonathanjr3/AudioWaveform's chart
///   types (Swift Charts and an HStack of capsules, their blue).
/// - Dots / Curve: lkora/WaveformScrubber's DotDrawer and BezierCurveDrawer
///   (mirrored dot pairs; smooth filled symmetric curve).
/// - Filled: AudioKit/Waveform's Metal min/max region, as a symmetric
///   filled path.
enum HUDWaveformStyle: String, CaseIterable {
    case article = "Article"
    case silver = "Silver"
    case capsules = "Capsules"
    case chartLine = "Chart Line"
    case chartArea = "Chart Area"
    case dots = "Dots"
    case curve = "Curve"
    case filled = "Filled"
}

/// The live waveform strip: levels reduced on the audio side (vDSP in
/// MicrophoneInput) drive whichever style is selected. Newest level on the
/// right. Replaces the draft text while listening.
struct HUDWaveformView: View {
    static let barCount = 56

    let content: DictationHUDContent

    @State private var start = Date()

    var body: some View {
        TimelineView(.animation) { context in
            styledWave
                // WWDC26-style finish over the drawn pixels: chromatic edge
                // fringing, a metallic specular sweep, and soft bloom
                // (WaveformSheen.metal), breathing with the voice.
                .layerEffect(
                    ShaderLibrary.waveformSheen(
                        .float2(waveSize),
                        .float(Float(context.date.timeIntervalSince(start))),
                        .float(Float(content.audioLevel))
                    ),
                    maxSampleOffset: CGSize(width: 8, height: 8)
                )
        }
        .onGeometryChange(for: CGSize.self, of: \.size) { waveSize = $0 }
        .animation(.linear(duration: 0.05), value: content.levelHistory)
        .padding(.horizontal, 28)
        .padding(.vertical, 6)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @State private var waveSize = CGSize(width: 1, height: 1)

    @ViewBuilder
    private var styledWave: some View {
        Group {
            switch content.waveformStyle {
            case .article:
                AudioWaveShape(samples: content.levelHistory, spacing: 2, rounded: false, perceptual: false)
                    .fill(silver)
            case .silver:
                AudioWaveShape(samples: content.levelHistory, spacing: 3, rounded: true, perceptual: true)
                    .fill(silver)
            case .capsules:
                capsules
            case .chartLine:
                chart(line: true)
            case .chartArea:
                chart(line: false)
            case .dots:
                DotWaveShape(samples: content.levelHistory, dotRadius: 1.6)
                    .fill(silver)
            case .curve:
                CurveWaveShape(samples: content.levelHistory)
                    .fill(silver)
            case .filled:
                FilledWaveShape(samples: content.levelHistory)
                    .fill(silver)
            }
        }
    }

    /// One color language for every style: the edge glow's white/silver —
    /// a hot white body cooling at the extremes, faint blue-violet fringe.
    /// Amber when the microphone dies (CONTEXT.md).
    private var silver: AnyShapeStyle {
        content.isAudioAlive
            ? AnyShapeStyle(LinearGradient(
                colors: [
                    Color(red: 0.62, green: 0.72, blue: 1.0).opacity(0.75),
                    .white,
                    Color(red: 0.62, green: 0.72, blue: 1.0).opacity(0.75),
                ],
                startPoint: .top,
                endPoint: .bottom
            ))
            : AnyShapeStyle(Color.orange.opacity(0.55))
    }

    /// AudioWaveform's capsule mode: dampened heights, width-derived bars.
    private var capsules: some View {
        GeometryReader { proxy in
            let values = content.levelHistory
            let step = proxy.size.width / CGFloat(values.count)
            let barWidth = max(step * 0.55, 1)
            HStack(alignment: .center, spacing: step - barWidth) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    Capsule()
                        .fill(silver)
                        .frame(
                            width: barWidth,
                            height: max(barWidth, CGFloat(value) * 0.75 * proxy.size.height)
                        )
                        .frame(maxHeight: .infinity, alignment: .center)
                }
            }
        }
    }

    /// AudioWaveform's line/area modes, straight from Swift Charts.
    private func chart(line: Bool) -> some View {
        Chart(Array(content.levelHistory.enumerated()), id: \.offset) { index, value in
            if line {
                LineMark(x: .value("t", index), y: .value("level", value))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(silver)
            } else {
                AreaMark(x: .value("t", index), y: .value("level", value))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(silver)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...1)
    }
}

/// One vertical bar per sample, centered on the midline. `rounded` and
/// `perceptual` (square-root heights) split the Article and Silver looks.
struct AudioWaveShape: Shape {
    let samples: [Float]
    let spacing: CGFloat
    var rounded = true
    var perceptual = true

    nonisolated func path(in rect: CGRect) -> Path {
        guard !samples.isEmpty else { return Path() }
        let count = CGFloat(samples.count)
        let barWidth = max(1, (rect.width - spacing * (count - 1)) / count)

        var path = Path()
        var x = rect.minX
        for sample in samples {
            let scaled = perceptual ? CGFloat(sample).squareRoot() : CGFloat(sample)
            let height = max(2, scaled * rect.height)
            let bar = CGRect(x: x, y: rect.midY - height / 2, width: barWidth, height: height)
            if rounded {
                path.addRoundedRect(
                    in: bar,
                    cornerSize: CGSize(width: barWidth / 2, height: barWidth / 2)
                )
            } else {
                path.addRect(bar)
            }
            x += barWidth + spacing
        }
        return path
    }
}

/// WaveformScrubber's DotDrawer: a mirrored pair of dots per sample.
struct DotWaveShape: Shape {
    let samples: [Float]
    let dotRadius: CGFloat

    nonisolated func path(in rect: CGRect) -> Path {
        guard !samples.isEmpty else { return Path() }
        let spacing = rect.width / CGFloat(samples.count)
        var path = Path()
        for (index, sample) in samples.enumerated() {
            let x = rect.minX + CGFloat(index) * spacing
            let halfHeight = CGFloat(sample) * rect.height / 2
            for y in [rect.midY - halfHeight, rect.midY + halfHeight] {
                path.addEllipse(in: CGRect(
                    x: x - dotRadius,
                    y: y - dotRadius,
                    width: dotRadius * 2,
                    height: dotRadius * 2
                ))
            }
        }
        return path
    }
}

/// WaveformScrubber's BezierCurveDrawer, simplified: a smooth symmetric
/// filled shape through midpoint quadratic curves.
struct CurveWaveShape: Shape {
    let samples: [Float]

    nonisolated func path(in rect: CGRect) -> Path {
        guard samples.count > 1 else { return Path() }
        let stepX = rect.width / CGFloat(samples.count - 1)
        let top = samples.enumerated().map { index, sample in
            CGPoint(
                x: rect.minX + CGFloat(index) * stepX,
                y: rect.midY - max(1, CGFloat(sample) * rect.height / 2)
            )
        }

        var path = Path()
        path.move(to: top[0])
        addSmoothLine(through: top, to: &path)
        let bottom = top.reversed().map { CGPoint(x: $0.x, y: 2 * rect.midY - $0.y) }
        path.addLine(to: bottom[0])
        addSmoothLine(through: bottom, to: &path)
        path.closeSubpath()
        return path
    }

    private nonisolated func addSmoothLine(through points: [CGPoint], to path: inout Path) {
        for i in 1..<points.count {
            let previous = points[i - 1]
            let current = points[i]
            let mid = CGPoint(x: (previous.x + current.x) / 2, y: (previous.y + current.y) / 2)
            path.addQuadCurve(to: mid, control: previous)
        }
        path.addLine(to: points[points.count - 1])
    }
}

/// AudioKit Waveform's look: a continuous symmetric min/max region.
struct FilledWaveShape: Shape {
    let samples: [Float]

    nonisolated func path(in rect: CGRect) -> Path {
        guard samples.count > 1 else { return Path() }
        let stepX = rect.width / CGFloat(samples.count - 1)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        for (index, sample) in samples.enumerated() {
            path.addLine(to: CGPoint(
                x: rect.minX + CGFloat(index) * stepX,
                y: rect.midY - max(0.75, CGFloat(sample) * rect.height / 2)
            ))
        }
        for (index, sample) in samples.enumerated().reversed() {
            path.addLine(to: CGPoint(
                x: rect.minX + CGFloat(index) * stepX,
                y: rect.midY + max(0.75, CGFloat(sample) * rect.height / 2)
            ))
        }
        path.closeSubpath()
        return path
    }
}

#Preview("Article") {
    HUDShellPreviewHarness(visual: .waveform, waveformStyle: .article)
}

#Preview("Silver") {
    HUDShellPreviewHarness(visual: .waveform, waveformStyle: .silver)
}

#Preview("Chart Area") {
    HUDShellPreviewHarness(visual: .waveform, waveformStyle: .chartArea)
}

#Preview("Dots") {
    HUDShellPreviewHarness(visual: .waveform, waveformStyle: .dots)
}

#Preview("Curve") {
    HUDShellPreviewHarness(visual: .waveform, waveformStyle: .curve)
}

#Preview("Filled") {
    HUDShellPreviewHarness(visual: .waveform, waveformStyle: .filled)
}