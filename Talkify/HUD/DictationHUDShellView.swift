import SwiftUI

/// What the HUD currently says. `@Observable` so the AppKit controller can
/// mutate it and the SwiftUI shell follows.
@MainActor
@Observable
final class DictationHUDContent {
    var text = ""
    /// Drives the reveal/dismiss animation.
    var isRevealed = false
    /// True only while listening — the visuals react to the microphone, so
    /// they leave when it stops.
    var showsVoiceVisual = false
    /// Smoothed microphone level, 0–1.
    var audioLevel: Double = 0
    /// Raw recent levels, newest last, one per waveform bar.
    var levelHistory = [Float](repeating: 0, count: HUDWaveformView.barCount)
    /// False once levels stop arriving while listening: a dead microphone
    /// must look different from silence (CONTEXT.md).
    var isAudioAlive = true
    /// Bumped once per session start; one-shot effects (the ripple) trigger
    /// on the change rather than on the listening state, so they never
    /// re-fire mid-session.
    var sessionEpoch = 0
}

/// The HUD's shape and surface, lifted from Tilebar's NotchIsland shell:
/// square against the top of the screen, rounded below, filleted into the
/// bezel on a real housing, hardware-black fill, drawn shadow. The hosting
/// window never resizes, so the shell top-aligns itself inside whatever frame
/// it is given.
struct DictationHUDShellView: View {
    /// With Reduce Motion every style is replaced by a quiet fade
    /// (CONTEXT.md: the HUD skips expand/collapse animation).
    private static let reducedMotionFade = Animation.easeOut(duration: 0.12)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let screen: HUDScreenSnapshot
    let settings: AppSettings
    let content: DictationHUDContent

    private var size: CGSize {
        HUDNotchGeometry.contentSize(
            for: screen,
            visualBandHeight: visualBandHeight,
            includesTextBand: showsTextBand
        )
    }

    /// Reduce Motion always shows the quiet level meter in its slim band;
    /// otherwise both animated visuals get the tall band — the waveform fills
    /// it, the glow keeps it as an empty stage so the silhouette has flanks
    /// for the light to wrap.
    private var visualBandHeight: CGFloat {
        guard content.showsVoiceVisual else { return 0 }
        if reduceMotion { return HUDNotchGeometry.visualBandHeight }
        return HUDNotchGeometry.waveBandHeight
    }

    /// Any animated visual replaces the draft text entirely while listening;
    /// with Reduce Motion the draft text always shows.
    private var showsTextBand: Bool {
        !(content.showsVoiceVisual && !reduceMotion)
    }

    private var filletSize: CGFloat {
        HUDNotchGeometry.filletSize(for: screen)
    }

    private var housingShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            bottomLeadingRadius: HUDNotchGeometry.bottomCornerRadius,
            bottomTrailingRadius: HUDNotchGeometry.bottomCornerRadius,
            style: .continuous
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Strip level with the housing: kept empty so text never collides
            // with the camera.
            Color.clear
                .frame(height: HUDNotchGeometry.closedSize(for: screen).height)
            if visualBandHeight > 0 {
                Group {
                    if reduceMotion {
                        HUDLevelMeterView(content: content)
                    } else if settings.voiceVisual == .waveform {
                        HUDWaveformView(settings: settings, content: content)
                    } else {
                        // The glow lives on the silhouette (edgeGlow overlay);
                        // its band is an empty stage.
                        Color.clear
                    }
                }
                .frame(height: visualBandHeight)
            }
            if showsTextBand {
                textBand
            }
        }
        .frame(width: size.width)
        .frame(minHeight: size.height, alignment: .top)
        .animation(
            settings.longDraftStyle == .growDown ? .spring(duration: 0.25, bounce: 0) : nil,
            value: content.text
        )
        .animation(.spring(duration: 0.25, bounce: 0), value: visualBandHeight)
        .background { housing }
        .overlay { edgeGlow }
            .overlay(alignment: .topLeading) { fillet(.leading) }
            .overlay(alignment: .topTrailing) { fillet(.trailing) }
            .opacity(revealOpacity)
            .scaleEffect(x: revealScale.x, y: revealScale.y, anchor: .top)
            .offset(y: revealOffset)
            .animation(revealAnimation, value: content.isRevealed)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var isParked: Bool {
        !content.isRevealed && !reduceMotion
    }

    /// Where position moves at all, hidden means at or above the window's top
    /// edge — never below — so no style can open a gap against the screen edge.
    private var revealOffset: CGFloat {
        guard isParked else { return 0 }
        switch settings.revealStyle {
        case .slide: return -(size.height + 20)
        case .unfurl, .bloom: return 0
        case .drift: return -14
        }
    }

    private var revealScale: (x: CGFloat, y: CGFloat) {
        guard isParked else { return (1, 1) }
        switch settings.revealStyle {
        case .slide, .drift: return (1, 1)
        case .unfurl: return (1, 0.001)
        case .bloom: return (0.55, 0.55)
        }
    }

    private var revealOpacity: Double {
        if reduceMotion {
            return content.isRevealed ? 1 : 0
        }
        switch settings.revealStyle {
        case .slide, .unfurl: return 1
        case .bloom, .drift: return content.isRevealed ? 1 : 0
        }
    }

    /// Bounce lives only in top-anchored scale (unfurl, bloom); the styles
    /// that move position (slide, drift) stay bounce-free, because a position
    /// overshoot would detach the shape from the screen edge.
    private var revealAnimation: Animation {
        if reduceMotion {
            return Self.reducedMotionFade
        }
        if content.isRevealed {
            switch settings.revealStyle {
            case .slide: return .spring(duration: 0.4, bounce: 0)
            case .unfurl: return .spring(duration: 0.45, bounce: 0.3)
            case .bloom: return .spring(duration: 0.4, bounce: 0.25)
            case .drift: return .easeOut(duration: 0.24)
            }
        }
        switch settings.revealStyle {
        case .slide, .unfurl, .bloom: return .spring(duration: 0.28, bounce: 0)
        case .drift: return .easeIn(duration: 0.18)
        }
    }

    /// Draft text lives in the band below the housing.
    private var textBand: some View {
        draftText
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 9)
            .frame(minHeight: HUDNotchGeometry.textBandHeight)
    }

    /// The single-line variants truncate the head — the newest words are what
    /// the speaker checks. Grow Down cannot: head truncation forces
    /// single-line rendering, so it wraps and truncates the tail only when
    /// the line cap is hit.
    @ViewBuilder
    private var draftText: some View {
        switch settings.longDraftStyle {
        case .tailOnly:
            Text(content.text)
                .lineLimit(1)
                .truncationMode(.head)
        case .growDown:
            Text(content.text)
                .lineLimit(4)
                .multilineTextAlignment(.center)
        case .shrinkToFit:
            Text(content.text)
                .lineLimit(1)
                .truncationMode(.head)
                .minimumScaleFactor(0.55)
        }
    }

    /// The ripple sits between the clip and the shadow: it displaces the
    /// housing's pixels, and the shadow outside the effect stays still
    /// instead of shimmering with the wave.
    private var housing: some View {
        // Plain values for the @Sendable keyframeAnimator content closure.
        let rippleOrigin = CGPoint(
            x: size.width / 2,
            y: HUDNotchGeometry.closedSize(for: screen).height
        )
        let rippleEnabled = !reduceMotion && settings.voiceVisual == .glow
        return Color.black
            .clipShape(housingShape)
            .keyframeAnimator(
                initialValue: 0.0,
                trigger: content.sessionEpoch
            ) { view, elapsed in
                view.modifier(
                    HUDRippleModifier(
                        origin: rippleOrigin,
                        elapsedTime: elapsed,
                        isEnabled: rippleEnabled
                    )
                )
            } keyframes: { _ in
                MoveKeyframe(0.0)
                LinearKeyframe(
                    HUDRippleModifier.duration,
                    duration: HUDRippleModifier.duration
                )
            }
            .shadow(color: .black.opacity(0.35), radius: 11, y: 4)
    }

    /// The edge-glow voice visual: an origin glow blooming from the notch
    /// housing along the open silhouette, breathing with the voice
    /// (HUDEdgeGlowView). Mounted whenever the variant is selected — not only
    /// while listening — so the drain-out ramp can render after the session
    /// ends; the view disables its shader once the ramp reaches zero.
    @ViewBuilder
    private var edgeGlow: some View {
        if !reduceMotion, settings.voiceVisual == .glow {
            HUDEdgeGlowView(content: content)
        }
    }

    /// Sits alongside the body rather than inside it. Absent on a display with
    /// no notch: the flare exists to meet a housing (ADR-0001).
    @ViewBuilder
    private func fillet(_ side: HorizontalEdge) -> some View {
        if filletSize > 0 {
            Color.black
                .frame(width: filletSize, height: filletSize)
                .clipShape(NotchFilletShape(side: side))
                .offset(x: side == .leading ? -filletSize : filletSize)
        }
    }
}

// Live previews in-file so edits to the shell re-render in place; the
// harness (HUDPreviews.swift) drives synthesized speech-like levels.

#Preview("Edge Glow") {
    HUDShellPreviewHarness(visual: .glow)
}

#Preview("Waveform") {
    HUDShellPreviewHarness(visual: .waveform)
}

#Preview("Draft · grow down") {
    HUDShellPreviewHarness(
        text: "A long draft that outgrows a single line wraps and grows the "
            + "shape downward, capped at four lines, so the newest words stay visible"
    )
}

#Preview("Message · simulated notch") {
    HUDShellPreviewHarness(screen: HUDPreviewScreen.external, text: "Secure field")
}
