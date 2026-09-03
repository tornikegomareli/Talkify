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
      shapingBandHeight: showsShapingLabel ? metrics.shapingBandHeight : 0
    )
  }

  /// Whether the shape carries the shaping label's strip. Derived from the
  /// content rather than latched: the pick is set before the reveal and is not
  /// cleared until the shaping phase or the next session, so the strip never
  /// appears mid-flight and never leaves under a retracting shape.
  private var showsShapingLabel: Bool {
    content.shapingChoiceLabel != nil
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
      if let pick = content.shapingChoiceLabel {
        HUDShapingLabel(
          text: "Shaping: \(pick)",
          palette: settings.glowPalette,
          scale: metrics.scale,
          level: content.audioLevel,
          reduceMotion: reduceMotion
        )
        .frame(height: metrics.shapingBandHeight)
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
          compactBandText
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      } else {
        bandText
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

  /// What the band says: the shaping caption once that phase starts, the
  /// draft until then.
  ///
  /// The caption takes the draft's place rather than a band of its own. A band
  /// appearing at release would grow the shape exactly as it is about to
  /// retract, and the draft it sat under still read "Listening…" while
  /// nothing was listening any more.
  @ViewBuilder
  private var bandText: some View {
    if let name = content.shapingName {
      shapingCaption(name)
    } else {
      draftText
    }
  }

  @ViewBuilder
  private var compactBandText: some View {
    if let name = content.shapingName {
      shapingCaption(name)
    } else {
      compactDraftText
    }
  }

  private func shapingCaption(_ name: String) -> some View {
    HUDShapingCaption(
      text: "Shaping with \(name)",
      scale: metrics.scale,
      reduceMotion: reduceMotion
    )
  }

  /// The room the language tag needs on each side.
  ///
  /// Symmetric, so a centered draft stays centered. It replaced a
  /// per-character estimate that overshot a language pair by 40%.
  private var tagInset: CGFloat {
    max(24, tagReserve(content.languageTag))
  }

  private func tagReserve(_ tag: String?) -> CGFloat {
    guard let tag, !tag.isEmpty else { return 0 }
    // The capsule's own padding, its inset from the shape's edge, and air
    // before the draft may start.
    return tagTextWidth(tag) + 4 * 2 + 12 + 8
  }

  /// A tag's text width, measured rather than estimated: a prompt name is
  /// typed by the user, so no per-character guess covers both "EN → ES" and
  /// whatever somebody calls their prompt. Unscaled, like every other number
  /// here; the caller applies the scale.
  private func tagTextWidth(_ tag: String) -> CGFloat {
    let width = (tag as NSString)
      .size(withAttributes: [.font: NSFont.systemFont(ofSize: 9, weight: .semibold)])
      .width
      // The tracking the label draws with, which the measurement does not
      // know about.
      + 0.5 * CGFloat(tag.count)
    // Capped: past this a name truncates rather than pushing the draft off
    // the shape entirely.
    return min(width.rounded(.up), Self.maximumTagTextWidth)
  }

  private static let maximumTagTextWidth: CGFloat = 150

  @ViewBuilder
  private var languageTag: some View {
    if let tag = content.languageTag {
      tagCapsule(tag)
        .padding(.leading, 12 * metrics.scale)
    }
  }

  private func tagCapsule(_ text: String) -> some View {
    Text(text)
      .font(.system(size: 9 * metrics.scale, weight: .semibold, design: .rounded))
      .tracking(0.5)
      .foregroundStyle(.white.opacity(0.72))
      .lineLimit(1)
      // A long prompt name shrinks rather than truncating: a pick whose name
      // is cut off is a pick the arrows chose blind.
      .truncationMode(.tail)
      .frame(width: tagTextWidth(text) * metrics.scale)
      .padding(.horizontal, 4 * metrics.scale)
      .padding(.vertical, 1.5 * metrics.scale)
      .background(Capsule(style: .continuous).fill(.white.opacity(0.13)))
      // Clears the housing, so a tag never sits beside the camera.
      .padding(.top, HUDNotchGeometry.closedSize(for: screen).height + 5 * metrics.scale)
      .allowsHitTesting(false)
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
/// It takes the live draft's place in the text band rather than a band of its
/// own, so the shape does not grow at the moment it is about to retract and
/// the phase never sits under a draft still reading "Listening…".
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

  private var font: Font { .system(size: 15 * scale, weight: .medium) }

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

