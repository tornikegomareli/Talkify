import SwiftUI

/// The waveform and level-meter voice visuals that live in the band between
/// the housing and the draft text. The edge glow draws on the shape itself
/// and is composed in the shell instead.
///
/// Silence and a dead microphone look different (CONTEXT.md): silence keeps a
/// live, faintly moving baseline fed by the room's noise floor; a dead
/// microphone freezes into a flat amber line.
struct HUDVoiceVisualView: View {
    static let barCount = 48

    let content: DictationHUDContent
    let showsMeter: Bool

    var body: some View {
        if showsMeter {
            meter
        } else {
            waveform
        }
    }

    /// Scrolling bar waveform: newest level enters on the right.
    private var waveform: some View {
        Canvas { context, size in
            let history = content.levelHistory
            let barWidth = size.width / CGFloat(Self.barCount)
            for (index, level) in history.enumerated() {
                let height = max(2, size.height * CGFloat(level))
                let rect = CGRect(
                    x: CGFloat(index) * barWidth + barWidth * 0.2,
                    y: (size.height - height) / 2,
                    width: barWidth * 0.6,
                    height: height
                )
                context.fill(
                    Path(roundedRect: rect, cornerRadius: barWidth * 0.3),
                    with: .color(barColor)
                )
            }
        }
        .padding(.horizontal, 40)
    }

    /// The Reduce Motion alternative: a quiet horizontal level bar.
    private var meter: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.15))
                Capsule()
                    .fill(barColor)
                    .frame(width: max(6, proxy.size.width * CGFloat(content.audioLevel)))
            }
            .frame(height: 4)
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 60)
    }

    private var barColor: Color {
        content.isAudioAlive ? .white.opacity(0.85) : .orange.opacity(0.6)
    }
}
