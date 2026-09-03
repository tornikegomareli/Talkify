import SwiftUI

/// What a Direct Dictation session puts inside the HUD: the housing-level
/// strip, the voice visual's band, and the draft text band. The shape itself,
/// its fillets and its reveal belong to `HUDSurface`, which every HUD surface
/// shares.
struct DictationHUDShellView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  let screen: HUDScreenSnapshot
  let settings: DictationSessionSettings
  let content: DictationHUDContent

  /// The shape's dimensions at the session's HUD size. Everything the user
  /// can resize is read from here; the housing band and fillets are not.
  ///
  /// Held to two floors at once: this display's, so the shape never ends up
  /// narrower than the housing it descends from, and the selected visual's, so
  /// a layout built around live text never shrinks past reading it.
  static func metrics(
    picked: HUDMetrics,
    screen: HUDScreenSnapshot,
    visual: HUDVoiceVisualStyle,
    reduceMotion: Bool
  ) -> HUDMetrics {
    HUDMetrics(
      scale: max(
        picked.scale,
        max(
          HUDNotchGeometry.minimumScale(for: screen),
          HUDMetrics.minimumScale(for: visual, reduceMotion: reduceMotion)
        )
      )
    )
  }

  private var metrics: HUDMetrics {
    Self.metrics(
      picked: settings.hudMetrics,
      screen: screen,
      visual: settings.voiceVisual,
      reduceMotion: reduceMotion
    )
  }

  private var size: CGSize {
    HUDNotchGeometry.contentSize(
      for: screen,
      metrics: metrics,
      visualBandHeight: visualBandHeight,
      includesTextBand: showsTextBand,
      shapingBandHeight: showsShapingBand ? metrics.shapingBandHeight : 0
    )
  }

  /// Whether the shape carries its shaping band. Derived from the content
  /// rather than latched: the cycling label is set before the reveal and
  /// neither field is cleared until the next session claims the shape, so the
  /// band never appears mid-flight and never leaves under a retracting shape.
  private var showsShapingBand: Bool {
    content.shapingName != nil || content.shapingChoice != nil
  }

  /// Reduce Motion always shows the quiet level meter in its slim band;
  /// otherwise both animated visuals get the tall band — the waveform fills
  /// it, the glow keeps it as an empty stage so the silhouette has flanks
  /// for the light to wrap. In the Shape live draft trades band for text:
  /// the glow drops the band entirely (the beam wraps the text band), the
  /// waveform compresses to the slim strip so strip + wrapped text still
  /// fit the fixed window.
  private var visualBandHeight: CGFloat {
    guard keepsVisualLayout else { return 0 }
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
    if !keepsVisualLayout || reduceMotion { return true }
    return settings.voiceVisual == .compact
  }

  /// Whether the bands stay as a listening session laid them out. Held through
  /// the retract so the shape never resizes while it is sliding away.
  private var keepsVisualLayout: Bool {
    content.showsVoiceVisual || content.isDismissing
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
    HUDSurface(
      screen: screen,
      metrics: metrics,
      revealStyle: settings.revealStyle,
      isRevealed: content.isRevealed,
      size: size,
      rippleTrigger: content.sessionEpoch,
      rippleEnabled: settings.voiceVisual == .glow,
      content: {
        bands
          // The tag hangs off the shell, not the text band: Waveform and Edge
          // Glow hide the band for the whole listening phase, which is exactly
          // when the live language needs naming. Padded below the housing so it
          // clears the camera, and an overlay so it never changes the fixed
          // window's size.
          .overlay(alignment: .topLeading) { languageTag }
          .animation(
            settings.longDraftStyle == .growDown ? .spring(duration: 0.25, bounce: 0) : nil,
            value: content.text
          )
          .animation(.spring(duration: 0.25, bounce: 0), value: visualBandHeight)
      },
      overlays: {
        particleCloud
        siriOrb
        edgeGlow
      }
    )
  }

  private var bands: some View {
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
      if showsShapingBand {
        shapingBand
      }
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
    .padding(.horizontal, tagInset * metrics.scale)
    .padding(.vertical, 9 * metrics.scale)
    .frame(minHeight: metrics.textBandHeight)
  }

  /// The room the tag needs on each side.
  ///
  /// 46 was measured for a two-letter tag. A translate session's tag is a pair
  /// ("EN → ES"), and reserving two letters' room would let a centered draft
  /// run under it, so each further character adds its own width at this size.
  private var tagInset: CGFloat {
    guard let tag = content.languageTag else { return 24 }
    return 46 + CGFloat(max(0, tag.count - 2)) * 6
  }

  /// The shaping band: a band of the shape itself, grown downward below the
  /// visuals and the draft the way the shape grows for a long draft — a
  /// detached pill under the island is rejected by feel (CONTEXT.md), and the
  /// centered plate this replaces sat over the visuals and Compact's live
  /// draft. While recording it carries the cycling carousel; through the
  /// shaping phase it names the prompt the finished words are shaped with.
  @ViewBuilder
  private var shapingBand: some View {
    Group {
      if let name = content.shapingName {
        HUDShapingCaption(
          text: "Shaping with \(name)",
          scale: metrics.scale,
          reduceMotion: reduceMotion
        )
      } else if let choice = content.shapingChoice {
        shapingCarousel(choice)
      }
    }
    .frame(maxWidth: .infinity)
    .frame(height: metrics.shapingBandHeight)
    .allowsHitTesting(false)
  }

  /// The cycling pick between the two picks the arrows would land on.
  ///
  /// No arrow glyphs: what Left lands on is drawn on the left, which says the
  /// same thing and says it about something the user can read. The pick is at
  /// reading size because the arrows change something otherwise invisible,
  /// and a caption too small to read from a glance at the notch defeats the
  /// reason the band is there.
  ///
  /// The slots are fixed width so the row never reflows as names change
  /// length, which is also what lets each slot clip its own slide.
  private func shapingCarousel(_ choice: ShapingChoice) -> some View {
    HStack(spacing: 0) {
      shapingSlot(choice.previous, choice: choice, isCurrent: false)
      shapingSlot(choice.current, choice: choice, isCurrent: true)
      shapingSlot(choice.next, choice: choice, isCurrent: false)
    }
    .animation(
      reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.86),
      value: choice.index
    )
  }

  private func shapingSlot(
    _ name: String,
    choice: ShapingChoice,
    isCurrent: Bool
  ) -> some View {
    Text(name)
      .font(
        .system(
          size: (isCurrent ? 17 : 13) * metrics.scale,
          weight: isCurrent ? .semibold : .regular
        )
      )
      .foregroundStyle(.white.opacity(isCurrent ? 1 : 0.3))
      .lineLimit(1)
      // A long prompt name shrinks to fit rather than truncating: a pick
      // whose name is cut off is a pick the arrows chose blind.
      .minimumScaleFactor(0.5)
      .id(name)
      .transition(slide(choice.direction))
      .frame(width: (isCurrent ? 190 : 150) * metrics.scale)
      .clipped()
  }

  /// Moves a name the way the press moved it: pressing Right carries the row
  /// leftward, so the arriving name enters from the trailing edge.
  private func slide(_ direction: Int) -> AnyTransition {
    guard !reduceMotion, direction != 0 else { return .opacity }
    let arriving: Edge = direction > 0 ? .trailing : .leading
    let leaving: Edge = direction > 0 ? .leading : .trailing
    return .asymmetric(
      insertion: .move(edge: arriving).combined(with: .opacity),
      removal: .move(edge: leaving).combined(with: .opacity)
    )
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
}

/// The shaping-phase caption, with a highlight sweeping through its letters.
///
/// The sweep replaced a determinate bar that filled toward the shaping
/// timeout. `FoundationModels` reports no progress at all, so a bar could only
/// ever time the wait rather than measure it, and a bar that reaches the end
/// on a request about to succeed reads as a failure. A sweep claims nothing
/// except that something is still running, which is the whole truth here, and
/// it is the visual language of the framework doing the work.
///
/// Reduce Motion drops the sweep and holds the caption at full strength, so
/// the phase still reads as active without anything moving.
private struct HUDShapingCaption: View {
  let text: String
  let scale: CGFloat
  let reduceMotion: Bool

  @State private var isSweeping = false

  private var font: Font { .system(size: 13 * scale, weight: .medium) }

  var body: some View {
    Text(text)
      .font(font)
      .foregroundStyle(.white.opacity(reduceMotion ? 0.85 : 0.6))
      .lineLimit(1)
      .minimumScaleFactor(0.6)
      .overlay { sweep }
      .onAppear { isSweeping = true }
  }

  @ViewBuilder
  private var sweep: some View {
    if !reduceMotion {
      GeometryReader { proxy in
        let band = max(proxy.size.width * 0.45, 1)
        LinearGradient(
          stops: [
            .init(color: .white.opacity(0), location: 0),
            .init(color: .white, location: 0.5),
            .init(color: .white.opacity(0), location: 1),
          ],
          startPoint: .leading,
          endPoint: .trailing
        )
        .frame(width: band)
        // Starts fully off the leading edge and ends fully off the trailing
        // one, so the highlight enters and leaves rather than fading in place.
        .offset(x: isSweeping ? proxy.size.width : -band)
        .animation(
          .linear(duration: 1.4).repeatForever(autoreverses: false),
          value: isSweeping
        )
      }
      // The glyphs are the window: the highlight only ever shows inside the
      // letters, never as a bar crossing the shape.
      .mask {
        Text(text)
          .font(font)
          .lineLimit(1)
          .minimumScaleFactor(0.6)
      }
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

#Preview("Shaping band · glow") {
  HUDShellPreviewHarness(visual: .glow, shapingChoice: "Remove filler words")
}

#Preview("Shaping band · compact") {
  HUDShellPreviewHarness(visual: .compact, shapingChoice: "Remove filler words")
}

