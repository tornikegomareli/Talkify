import SwiftUI

/// Hosts the edge-glow shader (EdgeGlow.metal): an origin glow that blooms out
/// of the notch housing along the HUD's open silhouette when a session starts,
/// breathes with the microphone level while listening, and drains back into
/// the housing when the session ends. Only a dead microphone changes it
/// (static amber). The view extends past the shape on the flanks and bottom so
/// the halo can spill outside the border.
///
/// The view stays mounted while the glow variant is selected — the session
/// ramp must keep rendering after `showsVoiceVisual` flips false or the
/// drain-out never plays; the shader is disabled once the ramp reaches zero.
struct HUDEdgeGlowView: View {
    /// Room the halo gets beyond the shape's border.
    nonisolated static let spill: CGFloat = 28
    /// Arc position of the glow origin on the silhouette: bottom-center of
    /// the shape, directly under the housing.
    nonisolated static let originS: Double = 0.5
    /// Duration of the bloom-in and drain-out ramps.
    nonisolated static let rampDuration: TimeInterval = 0.4

    let content: DictationHUDContent

    var body: some View {
        GeometryReader { proxy in
            // Captured as plain values: the keyframeAnimator content closure
            // is @Sendable, and the body re-evaluates on every level tick, so
            // the closure always carries fresh ones.
            let size = proxy.size
            let listening = content.showsVoiceVisual
            let amplitude = 0.25 + 2.75 * content.audioLevel
            let alive: Double = content.isAudioAlive ? 1 : 0
            Rectangle()
                .keyframeAnimator(
                    initialValue: 0.0,
                    trigger: listening
                ) { view, progress in
                    view.colorEffect(
                        ShaderLibrary.edgeGlow(
                            .float2(size),
                            .float4(
                                Self.spill,
                                0,
                                size.width - Self.spill * 2,
                                size.height - Self.spill
                            ),
                            .float(HUDNotchGeometry.bottomCornerRadius),
                            .float(Self.originS),
                            .float(progress),
                            // Silence keeps a faint steady rim; speech flares it.
                            .float(amplitude),
                            .float(alive)
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
        .padding(.horizontal, -Self.spill)
        .padding(.bottom, -Self.spill)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
