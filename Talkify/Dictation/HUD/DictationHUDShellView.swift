import SwiftUI

/// What a Direct Dictation session puts inside the HUD: the housing-level
/// strip, the voice visual's band, and the draft text band. The shape itself,
/// its fillets and its reveal belong to `HUDSurface`, which every HUD surface
/// shares.
struct DictationHUDShellView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  let screen: HUDScreenSnapshot
  let settings: DictationSessionSettings
  /// `@Bindable` so the editable-draft review's field can bind its text and
  /// selection straight into the shared content model.
  @Bindable var content: DictationHUDContent
  @FocusState private var draftFieldFocused: Bool

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
      visualBandHeight: bandLayout.visualBandHeight,
      includesTextBand: bandLayout.showsTextBand
    )
  }

  /// The band decisions for the current session state, computed in a pure
  /// value so the review-context rules (the draft never disappears while
  /// reviewing) are pinned by DictationBandLayoutTests instead of being
  /// view-private.
  private var bandLayout: DictationBandLayout {
    DictationBandLayout(
      showsVoiceVisual: content.showsVoiceVisual,
      isDismissing: content.isDismissing,
      isReviewing: content.isReviewing,
      reduceMotion: reduceMotion,
      voiceVisual: settings.voiceVisual,
      levelMeterBandHeight: metrics.visualBandHeight,
      waveBandHeight: metrics.waveBandHeight
    )
  }

  /// The tone of the review selection highlight, shared by the editable
  /// field's tint and the band's replacement-round highlight, so both read
  /// as the same selection family: translucent white that shades the
  /// background while the white text stays legible behind it.
  nonisolated private static let reviewHighlight = Color.white.opacity(0.4)

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
          .animation(.spring(duration: 0.25, bounce: 0), value: bandLayout.visualBandHeight)
          .animation(.spring(duration: 0.25, bounce: 0), value: content.isReviewing)
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
      if bandLayout.showsTextBand {
        textBand
      }
      if bandLayout.visualBandHeight > 0 {
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
        .frame(height: bandLayout.visualBandHeight)
      }
      // The housing cap, level with the bottom edge: kept empty so text
      // never collides with the cap.
      Color.clear
        .frame(height: HUDNotchGeometry.closedSize(for: screen).height)
    }
  }

  /// Draft text lives in the band below the housing. The editable-draft
  /// review swaps the whole band for the editable field while the draft is
  /// settled; while a replacement round listens under that review the band
  /// keeps the text with the compact indicator beside it and the selection
  /// it targets visibly highlighted, and the visual stays away from the
  /// text.
  @ViewBuilder
  private var textBand: some View {
    Group {
      if content.isReviewing && !content.showsVoiceVisual {
        editableDraftField
      } else if content.isReviewing && content.showsVoiceVisual {
        replacementRoundDraft
      } else if bandLayout.showsCompactBand {
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
    // The review keeps the field's height through a replacement round too,
    // so the shape does not shrink and jump while the user is speaking over
    // it. The compact band floats its indicator and text in that space.
    .frame(minHeight: content.isReviewing ? metrics.maxTextBandHeight : metrics.textBandHeight)
  }

  /// The replacement round's band: the compact indicator beside the draft,
  /// which stays fully visible with a translucent highlight behind exactly
  /// the range the round will commit.
  private var replacementRoundDraft: some View {
    HStack(alignment: .top, spacing: 10 * metrics.scale) {
      if !reduceMotion {
        HUDCompactIndicatorView(content: content, scale: metrics.scale)
          .padding(.top, 3 * metrics.scale)
      }
      replacementDraftText
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  /// The replacement round's draft text: the same long-draft semantics, but
  /// rendered from an attributed string so the selection the round is
  /// overwriting stays visibly highlighted as the words stream in place.
  @ViewBuilder
  private var replacementDraftText: some View {
    switch settings.longDraftStyle {
    case .tailOnly:
      highlightedDraftText
        .lineLimit(1)
        .truncationMode(.head)
    case .growDown:
      highlightedDraftText
        .lineLimit(4)
        .multilineTextAlignment(.leading)
    case .shrinkToFit:
      highlightedDraftText
        .lineLimit(1)
        .truncationMode(.head)
        .minimumScaleFactor(0.55)
    }
  }

  /// The draft with the replacement landing zone painted over it, as an
  /// attributed string: `content.replacementHighlight` is maintained by the
  /// controller in sync with `content.text` while a round listens.
  private var highlightedDraftText: Text {
    var attributed = AttributedString(content.text)
    if let range = content.replacementHighlight,
       let selected = Range(range, in: content.text),
       let start = AttributedString.Index(selected.lowerBound, within: attributed),
       let end = AttributedString.Index(selected.upperBound, within: attributed) {
      attributed[start..<end].backgroundColor = Self.reviewHighlight
    }
    return Text(attributed)
  }

  /// The editable-draft review field: the finished draft, editable in place
  /// with the keyboard (cursor, selection, delete, typing). Plain Return is
  /// swallowed by the event tap and pastes; ⌥↩ inserts a newline. The panel
  /// is non-activating, so editing never activates Talkify — the previously
  /// focused control stays frontmost and takes key back the moment the
  /// review ends.
  ///
  /// The tint is translucent white: at full white the selection highlight
  /// would be the same colour as the draft text, making selected words
  /// unreadable; at partial opacity the highlight shades the background
  /// while the white text stays legible behind it.
  @ViewBuilder
  private var editableDraftField: some View {
    TextEditor(text: $content.text, selection: $content.selection)
      .font(.system(size: 15 * metrics.scale, weight: .medium))
      .foregroundStyle(.white)
      .tint(Self.reviewHighlight)
      .scrollContentBackground(.hidden)
      .scrollIndicators(.hidden)
      .focused($draftFieldFocused)
      .frame(minHeight: metrics.maxTextBandHeight)
      .onAppear {
        // The field takes focus the moment the review starts; the panel
        // is already key by then (HUDStage.enableDraftEditing).
        draftFieldFocused = true
      }
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
        // Hangs off the floating top edge; nothing hugs the shape there.
        .padding(.top, 6 * metrics.scale)
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
  /// so its drain-out ramp can render too, but stood down while a
  /// replacement round listens — the review's text owns the shape then.
  @ViewBuilder
  private var particleCloud: some View {
    if !reduceMotion,
     settings.voiceVisual == .glow,
     settings.glowCenter == .particles,
     !bandLayout.isReplacementRoundListening {
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
     content.showsVoiceVisual,
     !bandLayout.isReplacementRoundListening {
      HUDSiriOrbView(content: content, side: size.height - 8 * metrics.scale)
    }
  }

  /// The edge-glow voice visual: an origin glow blooming from the notch
  /// housing along the open silhouette, breathing with the voice
  /// (HUDEdgeGlowView). Mounted whenever the variant is selected — not only
  /// while listening — so the drain-out ramp can render after the session
  /// ends; the view disables its shader once the ramp reaches zero. Stood
  /// down while a replacement round listens: the review's text owns the
  /// shape then.
  @ViewBuilder
  private var edgeGlow: some View {
    if !reduceMotion,
     settings.voiceVisual == .glow,
     !bandLayout.isReplacementRoundListening {
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

