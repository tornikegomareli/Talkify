import SwiftUI

/// The live waveform, built the way "Writing a High-Performance Audio Wave in
/// SwiftUI" does it: levels reduced on the audio side (vDSP in
/// MicrophoneInput) feed a plain Shape of vertical bars — no per-frame shader
/// or canvas work, just a cheap path rebuild per level tick. Newest bar on
/// the right, Voice Memos style. Replaces the draft text while listening.
struct HUDWaveformView: View {
    static let barCount = 56

    let content: DictationHUDContent

    var body: some View {
        AudioWaveShape(samples: content.levelHistory, spacing: 3)
            .fill(fill)
            .animation(.linear(duration: 0.05), value: content.levelHistory)
            .padding(.horizontal, 28)
            .padding(.vertical, 6)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// Silver-white bars, brightest in the middle band where the newest
    /// motion lives; a dead microphone turns the whole strip amber.
    private var fill: some ShapeStyle {
        content.isAudioAlive
            ? AnyShapeStyle(LinearGradient(
                colors: [.white.opacity(0.55), .white, .white.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            ))
            : AnyShapeStyle(Color.orange.opacity(0.55))
    }
}

/// One rounded vertical bar per sample, centered on the midline, height
/// perceptually scaled (square root) so quiet speech still moves the strip.
struct AudioWaveShape: Shape {
    let samples: [Float]
    let spacing: CGFloat

    nonisolated func path(in rect: CGRect) -> Path {
        guard !samples.isEmpty else { return Path() }
        let count = CGFloat(samples.count)
        let barWidth = max(1, (rect.width - spacing * (count - 1)) / count)

        var path = Path()
        var x = rect.minX
        for sample in samples {
            let scaled = CGFloat(sample).squareRoot()
            let height = max(2, scaled * rect.height)
            path.addRoundedRect(
                in: CGRect(
                    x: x,
                    y: rect.midY - height / 2,
                    width: barWidth,
                    height: height
                ),
                cornerSize: CGSize(width: barWidth / 2, height: barWidth / 2)
            )
            x += barWidth + spacing
        }
        return path
    }
}

#Preview("Waveform · live") {
    HUDShellPreviewHarness(visual: .waveform)
}

#Preview("Waveform · dead mic") {
    HUDShellPreviewHarness(visual: .waveform, micAlive: false)
}