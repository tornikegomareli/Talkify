import SwiftUI

/// Hosts the Metal waveform (DictationWave.metal): a full-band voice visual
/// that replaces the draft text while listening.
struct HUDWaveformView: View {
    let content: DictationHUDContent

    @State private var start = Date()

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation) { context in
                Rectangle()
                    .colorEffect(
                        ShaderLibrary.dictationWave(
                            .float2(proxy.size),
                            .float(Float(context.date.timeIntervalSince(start))),
                            .float(Float(content.audioLevel)),
                            .float(content.isAudioAlive ? 1 : 0)
                        )
                    )
            }
        }
        .padding(.horizontal, 24)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Oversized canvas for tuning the shader's constants in isolation —
/// amplitude, glow falloff, hue drift all live in DictationWave.metal.
#Preview("Waveform shader · large") {
    WaveformShaderPreview()
}

#Preview("Waveform shader · dead mic") {
    WaveformShaderPreview(micAlive: false)
}

private struct WaveformShaderPreview: View {
    var micAlive = true

    @State private var content = DictationHUDContent()

    var body: some View {
        HUDWaveformView(content: content)
            .frame(width: 640, height: 160)
            .background(.black)
            .task {
                content.isAudioAlive = micAlive
                guard micAlive else { return }
                var t = 0.0
                while !Task.isCancelled {
                    let burst = max(0, sin(t * 5.6))
                    let raw = 0.05 + burst * (0.3 + 0.35 * Double.random(in: 0...1))
                    content.audioLevel = max(raw, content.audioLevel * 0.88)
                    t += 0.022
                    try? await Task.sleep(for: .milliseconds(22))
                }
            }
    }
}
