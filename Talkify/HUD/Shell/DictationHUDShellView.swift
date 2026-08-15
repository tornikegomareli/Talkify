import SwiftUI

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
  let settings: DictationSessionSettings
  let content: DictationHUDContent

  /// The shape's dimensions at the session's HUD size. Everything the user
  /// can resize is read from here; the housing band and fillets are not.
  private var metrics: HUDMetrics {
    settings.hudMetrics
  }

  private var size: CGSize {
    HUDNotchGeometry.contentSize(
      for: screen,
      metrics: metrics,
      visualBandHeight: visualBandHeight,
      includesTextBand: showsTextBand
    )
  }

  /// Reduce Motion always shows the quiet level meter in its slim band;
  /// otherwise both animated visuals get the tall band — the waveform fills
  /// it, the glow keeps it as an empty stage so the silhouette has flanks
  /// for the light to wrap. In the Shape live draft trades band for text:
  /// the glow drops the band entirely (the beam wraps the text band), the
  /// waveform compresses to the slim strip so strip + wrapped text still
  /// fit the fixed window.
  private var visualBandHeight: CGFloat {
    guard content.showsVoiceVisual else { return 0 }
    if reduceMotion { return metrics.visualBandHeight }
    // Compact has no band of its own: its indicator lives inside the
    // text band, beside the draft.
    if settings.voiceVisual == .compact { return 0 }
    return metrics.waveBandHeight
  }

  /// Waveform and Edge Glow replace the draft text entirely while
  /// listening; Compact is built around it. With Reduce Motion the draft
  /// text always shows.
  private var showsTextBand: Bool {
    if !content.showsVoiceVisual || reduceMotion { return true }
    return settings.voiceVisual == .compact
  }

  /// Whether the text band renders the Compact layout: the voice indicator
  /// beside a leading-aligned draft. Not gated on the listening state —
  /// swapping the band's structure at finalize reads as a glitch mid
  /// retract, so the layout stays and the indicator settles instead.
  private var showsCompactBand: Bool {
    settings.voiceVisual == .compact && !reduceMotion
  }


  private var filletSize: CGFloat {
    HUDNotchGeometry.filletSize(for: screen)
  }

  private var housingShape: UnevenRoundedRectangle {
    UnevenRoundedRectangle(
      bottomLeadingRadius: metrics.bottomCornerRadius,
      bottomTrailingRadius: metrics.bottomCornerRadius,
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
            // Edge Glow: the centers (particles, orb) are
            // shape-wide overlays, so the band is an empty stage.
            Color.clear
          }
        }
        .frame(height: visualBandHeight)
      }
      if showsTextBand {
        textBand
      }
    }
    // The tag hangs off the shell, not the text band: Waveform and Edge Glow
    // hide the band for the whole listening phase, which is exactly when the
    // live language needs naming. Padded below the housing so it clears the
    // camera, and an overlay so it never changes the fixed window's size.
    .overlay(alignment: .topLeading) { languageTag }
    .frame(width: size.width)
    .frame(minHeight: size.height, alignment: .top)
    .animation(
      settings.longDraftStyle == .growDown ? .spring(duration: 0.25, bounce: 0) : nil,
      value: content.text
    )
    .animation(.spring(duration: 0.25, bounce: 0), value: visualBandHeight)
    .background { housing }
    .overlay { particleCloud }
    .overlay { siriOrb }
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

  /// Draft text lives in the band below the housing. Compact puts its
  /// voice indicator on the leading side, Dynamic Island-style, with the
  /// draft leading-aligned beside it; the other visuals center the draft.
  @ViewBuilder
  private var textBand: some View {
    Group {
      if showsCompactBand {
        HStack(alignment: .top, spacing: 10 * metrics.scale) {
          HUDCompactIndicatorView(content: content, scale: metrics.scale)
            .padding(.top, 3 * metrics.scale)
          compactDraftText
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      } else {
        draftText
      }
    }
    .font(.system(size: 15 * metrics.scale, weight: .medium))
    .foregroundStyle(.white)
    // The tag sits in the inset rather than in the flow, and the inset grows
    // on both sides, so centered drafts stay centered and nothing overlaps.
    .padding(.horizontal, (content.languageTag == nil ? 24 : 46) * metrics.scale)
    .padding(.vertical, 9 * metrics.scale)
    .frame(minHeight: metrics.textBandHeight)
  }

  @ViewBuilder
  private var languageTag: some View {
    if let tag = content.languageTag {
      Text(tag)
        .font(.system(size: 9 * metrics.scale, weight: .semibold, design: .rounded))
        .tracking(0.5)
        .foregroundStyle(.white.opacity(0.72))
        .padding(.horizontal, 4 * metrics.scale)
        .padding(.vertical, 1.5 * metrics.scale)
        .background(Capsule(style: .continuous).fill(.white.opacity(0.13)))
        .padding(.leading, 12 * metrics.scale)
        // Clears the housing, so the tag never sits beside the camera.
        .padding(.top, HUDNotchGeometry.closedSize(for: screen).height + 5 * metrics.scale)
        .allowsHitTesting(false)
    }
  }

  /// The Compact draft: the same long-draft semantics, leading-aligned so
  /// the text hangs off the indicator instead of floating centered.
  @ViewBuilder
  private var compactDraftText: some View {
    switch settings.longDraftStyle {
    case .tailOnly:
      Text(content.text)
        .lineLimit(1)
        .truncationMode(.head)
    case .growDown:
      Text(content.text)
        .lineLimit(4)
        .multilineTextAlignment(.leading)
    case .shrinkToFit:
      Text(content.text)
        .lineLimit(1)
        .truncationMode(.head)
        .minimumScaleFactor(0.55)
    }
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
      .shadow(color: .black.opacity(0.35), radius: 11 * metrics.scale, y: 4 * metrics.scale)
  }

  /// The Edge Glow particle cloud, clipped to the housing so no mote leaks
  /// past the silhouette. Mounted with the glow (not only while listening)
  /// so its drain-out ramp can render too.
  @ViewBuilder
  private var particleCloud: some View {
    if !reduceMotion, settings.voiceVisual == .glow, settings.glowCenter == .particles {
      HUDParticleCloudView(
        content: content,
        settings: settings,
        cornerRadius: metrics.bottomCornerRadius,
        topFilletRadius: filletSize
      )
        .clipShape(housingShape)
    }
  }

  /// The Edge Glow's orb center: centered on the whole notch island rather
  /// than tucked in the band, sized just short of the island's height.
  /// Gated on the listening state — as an overlay it no longer disappears
  /// with the band, so it must gate itself.
  @ViewBuilder
  private var siriOrb: some View {
    if !reduceMotion,
     settings.voiceVisual == .glow,
     settings.glowCenter == .siriOrb,
     content.showsVoiceVisual {
      HUDSiriOrbView(content: content, side: size.height - 8 * metrics.scale)
    }
  }

  /// The edge-glow voice visual: an origin glow blooming from the notch
  /// housing along the open silhouette, breathing with the voice
  /// (HUDEdgeGlowView). Mounted whenever the variant is selected — not only
  /// while listening — so the drain-out ramp can render after the session
  /// ends; the view disables its shader once the ramp reaches zero.
  @ViewBuilder
  private var edgeGlow: some View {
    if !reduceMotion, settings.voiceVisual == .glow {
      HUDEdgeGlowView(
        content: content,
        settings: settings,
        metrics: metrics,
        topFilletRadius: filletSize
      )
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

