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
      // Waveform + Draft has no visual band; its hanging stage is 40
      // points, 4 more than the ordinary text band. That extra has to be
      // in the declared size or Slide parks short of hiding the island.
      visualBandHeight: visualBandHeight
        + (showsRecentDraft
          ? metrics.waveDraftStageHeight - metrics.textBandHeight : 0),
      includesTextBand: showsTextBand,
      shapingBandHeight: showsShapingLabel ? metrics.shapingBandHeight : 0
    )
  }

  /// Whether the shape carries the shaping label's strip. Derived from the
  /// content rather than latched: the pick is set before the reveal and is not
  /// cleared until the shaping phase or the next session, so the strip never
  /// appears mid-flight and never leaves under a retracting shape.
  private var showsShapingLabel: Bool {
    shapingLabel != nil
  }

  /// The caption and what its color follows: the pick while speaking, then the
  /// prompt the finished words are going through. One strip for both, so the
  /// shape neither grows nor loses it at the handover.
  private var shapingLabel: (text: String, activity: HUDShapingLabel.Activity)? {
    if let name = content.shapingName {
      return ("Shaping with \(name)", .working)
    }
    if let pick = content.shapingChoiceLabel {
      return ("Shaping: \(pick)", .voice(content.audioLevel))
    }
    return nil
  }

  /// Reduce Motion always shows the quiet level meter in its slim band.
  /// Compact and Waveform + Draft have no band of their own: Compact's
  /// indicator and Waveform + Draft's Chart Line live inside the text band,
  /// so the words start higher. Waveform and Edge Glow keep the tall band —
  /// the waveform fills it, the glow keeps it as an empty stage so the
  /// silhouette has flanks for the light to wrap.
  private var visualBandHeight: CGFloat {
    guard keepsVisualLayout else { return 0 }
    if reduceMotion { return metrics.visualBandHeight }
    switch settings.voiceVisual {
    case .compact, .waveDraft: return 0
    case .waveform, .glow: return metrics.waveBandHeight
    }
  }

  /// Waveform and Edge Glow replace the draft text entirely while
  /// listening; Compact and Waveform + Draft are built around it. With
  /// Reduce Motion the draft text always shows.
  private var showsTextBand: Bool {
    if !keepsVisualLayout || reduceMotion { return true }
    return settings.voiceVisual.showsDraftWhileListening
  }

  /// Whether the bands stay as a listening session laid them out. Held through
  /// the retract so the shape never resizes while it is sliding away.
  private var keepsVisualLayout: Bool {
    content.showsVoiceVisual || content.isDismissing
  }

  /// Whether the text band is Compact's leading-aligned draft. Not gated on
  /// the listening state — swapping the band's structure at finalize reads
  /// as a glitch mid retract, so the layout stays and the indicator settles
  /// instead. Waveform + Draft has its own centered stage.
  private var showsLeadingDraft: Bool {
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
      rippleEnabled: settings.voiceVisual.usesEdgeGlow,
      content: {
        bands
          // The tag hangs off the shell, not the text band: Waveform and Edge
          // Glow hide the band for the whole listening phase, which is exactly
          // when the live language needs naming. Padded below the housing so it
          // clears the camera, and an overlay so it never changes the fixed
          // window's size. Waveform + Draft places its own tag on the island.
          .overlay(alignment: .topLeading) {
            if !showsRecentDraft { languageTag }
          }
          // Grow Down springs the island's height. Glyphs opt out so new
          // words land immediately; the token is coarse so a wrap is one spring.
          .animation(
            settings.longDraftStyle == .growDown && !showsRecentDraft
              ? .spring(duration: 0.18, bounce: 0) : nil,
            value: draftHeightToken
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
      island
      if let label = shapingLabel {
        HUDShapingLabel(
          text: label.text,
          palette: settings.glowPalette,
          scale: metrics.scale,
          activity: label.activity,
          reduceMotion: reduceMotion
        )
        .frame(height: metrics.shapingBandHeight)
      }
    }
  }

  /// Housing plus the bands below it. Waveform + Draft's recent-word line
  /// is an overlay on this silhouette, not a ZStack sibling: a
  /// max-height-infinity child in a ZStack expands to the host window and
  /// the black shape follows it. Overlay stays the stacked size, and the
  /// words center in the box the glow wraps — including the housing
  /// flanks, which are visible even though the camera sits in the middle.
  private var island: some View {
    stackedBands
      .overlay {
        if showsRecentDraft {
          HUDRecentDraftText(
            committed: content.text,
            volatile: content.volatileText,
            scale: metrics.scale
          )
          .padding(.horizontal, tagInset * metrics.scale)
        }
      }
      // The ribbon sits at the top of the stage and the words are centered in
      // the whole island, so the line crosses them and paints over the glyphs.
      // That is the chosen look, not an oversight: reviewed and kept.
      .overlay(alignment: .top) {
        if showsRecentDraft, showsWaveDraftRibbon {
          HUDCompactChartLineView(content: content, scale: metrics.scale)
            .frame(height: metrics.ribbonBandHeight)
            .padding(.top, HUDNotchGeometry.closedSize(for: screen).height)
            .padding(.horizontal, tagInset * metrics.scale)
        }
      }
      .overlay(alignment: .leading) {
        if showsRecentDraft { languageTag }
      }
  }

  private var stackedBands: some View {
    VStack(spacing: 0) {
      // Strip level with the housing: kept empty so text never collides
      // with the camera. Waveform + Draft still counts it in the box the
      // words are centered in, because the flanks of that strip are visible.
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
  }

  /// Draft text lives in the band below the housing. Compact puts its
  /// voice indicator on the leading side, Dynamic Island-style, with the
  /// draft leading-aligned beside it. Waveform + Draft only reserves the
  /// hanging stage here; the words themselves overlay the whole island.
  /// The other visuals center the draft.
  @ViewBuilder
  private var textBand: some View {
    if showsRecentDraft {
      Color.clear
        .frame(height: metrics.waveDraftStageHeight)
    } else {
      Group {
        if showsLeadingDraft {
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
      .padding(.top, 9 * metrics.scale)
      .padding(.bottom, 9 * metrics.scale)
      .frame(minHeight: metrics.textBandHeight)
    }
  }

  private var showsRecentDraft: Bool {
    Self.showsRecentDraft(
      visual: settings.voiceVisual,
      listening: content.showsVoiceVisual,
      dismissing: content.isDismissing,
      shaping: content.shapingName != nil,
      reduceMotion: reduceMotion
    )
  }

  private var showsWaveDraftRibbon: Bool {
    Self.showsRibbon(
      visual: settings.voiceVisual,
      listening: content.showsVoiceVisual,
      dismissing: content.isDismissing,
      shaping: content.shapingName != nil,
      reduceMotion: reduceMotion,
      ribbonEnabled: settings.waveDraftShowsRibbon
    )
  }

  /// Waveform + Draft's recent-word line. Same occupancy as the ribbon:
  /// listening, retracting, and shaping keep it; a status message does not.
  static func showsRecentDraft(
    visual: HUDVoiceVisualStyle,
    listening: Bool,
    dismissing: Bool,
    shaping: Bool,
    reduceMotion: Bool
  ) -> Bool {
    visual == .waveDraft && !reduceMotion && (listening || dismissing || shaping)
  }

  /// Compact keeps its indicator through shaping and retracts; the recent
  /// draft does the same, but a status message is a new occupant and must
  /// not inherit the last session's audio or the extra 24 points of height.
  static func showsRibbon(
    visual: HUDVoiceVisualStyle,
    listening: Bool,
    dismissing: Bool,
    shaping: Bool,
    reduceMotion: Bool,
    ribbonEnabled: Bool = true
  ) -> Bool {
    ribbonEnabled && showsRecentDraft(
      visual: visual,
      listening: listening,
      dismissing: dismissing,
      shaping: shaping,
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
        // Waveform + Draft overlays the tag on the whole island, so it
        // shares the draft's vertical center. Other visuals pin it below
        // the housing from the shell.
        .padding(.top, showsRecentDraft ? 0 : tagTopInset)
        .allowsHitTesting(false)
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
  }

  private var tagTopInset: CGFloat {
    let housing = HUDNotchGeometry.closedSize(for: screen).height
    let belowHousing: CGFloat
    if showsTextBand, visualBandHeight > 0 {
      belowHousing = visualBandHeight + 5 * metrics.scale
    } else {
      belowHousing = 5 * metrics.scale
    }
    return housing + belowHousing
  }

  /// Coarse height for Grow Down's spring: one step per ~40 characters, so
  /// wrapping animates the island without tweening every volatile letter.
  private var draftHeightToken: Int {
    (content.text.count + content.volatileText.count) / 40
  }

  /// Committed draft in full white, the current guess lighter, so new words
  /// show as soon as the recognizer emits them. Glyphs opt out of Grow Down's
  /// height spring so they do not fade in with it.
  private var liveDraft: some View {
    let committed = AttributedString(content.text)
    var guess = AttributedString(content.volatileText)
    guess.font = .system(size: 15 * metrics.scale, weight: .regular)
    guess.foregroundColor = Color.white.opacity(0.55)
    return Text(committed + guess)
      .transaction { $0.animation = nil }
  }

  /// The Compact draft: the same long-draft semantics, leading-aligned so
  /// the text hangs off the indicator instead of floating centered.
  @ViewBuilder
  private var compactDraftText: some View {
    switch settings.longDraftStyle {
    case .tailOnly:
      liveDraft
        .lineLimit(1)
        .truncationMode(.head)
    case .growDown:
      liveDraft
        .lineLimit(4)
        .multilineTextAlignment(.leading)
    case .shrinkToFit:
      liveDraft
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
      liveDraft
        .lineLimit(1)
        .truncationMode(.head)
    case .growDown:
      liveDraft
        .lineLimit(4)
        .multilineTextAlignment(.center)
    case .shrinkToFit:
      liveDraft
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
    if !reduceMotion, settings.voiceVisual.usesEdgeGlow {
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

#Preview("Waveform + Draft") {
  HUDShellPreviewHarness(visual: .waveDraft)
}

#Preview("Waveform + Draft · dead mic") {
  HUDShellPreviewHarness(visual: .waveDraft, micAlive: false)
}

