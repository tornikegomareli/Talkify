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
