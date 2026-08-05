import SwiftUI

/// What the HUD currently says. `@Observable` so the AppKit controller can
/// mutate it and the SwiftUI shell follows.
@MainActor
@Observable
final class DictationHUDContent {
    var text = ""
    /// Drives the reveal/dismiss animation.
    var isRevealed = false
    /// Slide is the chosen default; the others stay for the Settings picker.
    var revealStyle = HUDRevealStyle.slide
    /// Grow Down is the chosen default; the others stay for the Settings picker.
    var longDraftStyle = HUDLongDraftStyle.growDown
    var voiceVisualStyle = HUDVoiceVisualStyle.waveform
    /// True only while listening — the visuals react to the microphone, so
    /// they leave when it stops.
    var showsVoiceVisual = false
    /// Smoothed microphone level, 0–1.
    var audioLevel: Double = 0
    /// False once levels stop arriving while listening: a dead microphone
    /// must look different from silence (CONTEXT.md).
    var isAudioAlive = true
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
    let content: DictationHUDContent

    private var size: CGSize {
        HUDNotchGeometry.contentSize(
            for: screen,
            visualBandHeight: visualBandHeight,
            includesTextBand: showsTextBand
        )
    }

    /// Reduce Motion always shows the quiet level meter in its slim band;
    /// otherwise the waveform gets its tall band and the glow needs none.
    private var visualBandHeight: CGFloat {
        guard content.showsVoiceVisual else { return 0 }
        if reduceMotion { return HUDNotchGeometry.visualBandHeight }
        return content.voiceVisualStyle == .waveform ? HUDNotchGeometry.waveBandHeight : 0
    }

    /// The waveform replaces the draft text entirely while listening.
    private var showsTextBand: Bool {
        !(content.showsVoiceVisual && !reduceMotion && content.voiceVisualStyle == .waveform)
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
                    } else {
                        HUDWaveformView(content: content)
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
            content.longDraftStyle == .growDown ? .spring(duration: 0.25, bounce: 0) : nil,
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
        switch content.revealStyle {
        case .slide: return -(size.height + 20)
        case .unfurl, .bloom: return 0
        case .drift: return -14
        }
    }

    private var revealScale: (x: CGFloat, y: CGFloat) {
        guard isParked else { return (1, 1) }
        switch content.revealStyle {
        case .slide, .drift: return (1, 1)
        case .unfurl: return (1, 0.001)
        case .bloom: return (0.55, 0.55)
        }
    }

    private var revealOpacity: Double {
        if reduceMotion {
            return content.isRevealed ? 1 : 0
        }
        switch content.revealStyle {
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
            switch content.revealStyle {
            case .slide: return .spring(duration: 0.4, bounce: 0)
            case .unfurl: return .spring(duration: 0.45, bounce: 0.3)
            case .bloom: return .spring(duration: 0.4, bounce: 0.25)
            case .drift: return .easeOut(duration: 0.24)
            }
        }
        switch content.revealStyle {
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
        switch content.longDraftStyle {
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

    private var housing: some View {
        Color.black
            .clipShape(housingShape)
            .shadow(color: .black.opacity(0.35), radius: 11, y: 4)
    }

    /// The edge-glow voice visual: a white/silver comet sweeping the open
    /// silhouette — corner to notch and back, never across the hidden top
    /// edge — with brightness following the voice (HUDEdgeGlowView).
    @ViewBuilder
    private var edgeGlow: some View {
        if content.showsVoiceVisual, !reduceMotion, content.voiceVisualStyle == .glow {
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
