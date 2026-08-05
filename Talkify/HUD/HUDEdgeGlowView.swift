import SwiftUI

/// Hosts the edge-glow shader (EdgeGlow.metal): a hot silver comet with a
/// fading tail sweeping the HUD's open silhouette — corner to notch and back,
/// never across the hidden top edge — its brightness following the voice.
/// The view extends past the shape on the flanks and bottom so the halo can
/// spill outside the border.
struct HUDEdgeGlowView: View {
    /// Room the halo gets beyond the shape's border.
    static let spill: CGFloat = 28

    let content: DictationHUDContent

    @State private var start = Date()

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation) { context in
                Rectangle()
                    .colorEffect(
                        ShaderLibrary.edgeGlow(
                            .float2(proxy.size),
                            .float4(
                                Self.spill,
                                0,
                                proxy.size.width - Self.spill * 2,
                                proxy.size.height - Self.spill
                            ),
                            .float(HUDNotchGeometry.bottomCornerRadius),
                            .float(Float(context.date.timeIntervalSince(start))),
                            .float(Float(content.audioLevel)),
                            .float(content.isAudioAlive ? 1 : 0),
                            .float(Float(
                                content.lastPulseAt.map {
                                    context.date.timeIntervalSince($0)
                                } ?? 99
                            ))
                        )
                    )
            }
        }
        .padding(.horizontal, -Self.spill)
        .padding(.bottom, -Self.spill)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview("Edge glow · live") {
    HUDShellPreviewHarness(visual: .glow)
}

#Preview("Edge glow · dead mic") {
    HUDShellPreviewHarness(visual: .glow, micAlive: false)
}
