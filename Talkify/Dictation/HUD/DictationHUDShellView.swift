import SwiftUI

/// What a Direct Dictation session puts inside the HUD: the housing-level
/// strip, the voice visual's band, and the draft text band. The shape itself,
/// its fillets and its reveal belong to `HUDSurface`, which every HUD surface
/// shares.
struct DictationHUDShellView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @FocusState private var isDraftFocused: Bool

  let screen: HUDScreenSnapshot
  let settings: DictationSessionSettings
  let content: DictationHUDContent
  let stage: HUDStage?

  init(screen: HUDScreenSnapshot, settings: DictationSessionSettings, content: DictationHUDContent, stage: HUDStage? = nil) {
    self.screen = screen
    self.settings = settings
    self.content = content
    self.stage = stage
  }

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
          editableDraft(alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      } else {
        editableDraft(alignment: .center)
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

  @ViewBuilder
  private func editableDraft(alignment: TextAlignment) -> some View {
    if content.isEditable {
      TextField("", text: Binding(get: { content.text }, set: { content.text = $0 }))
        .textFieldStyle(.plain)
        .multilineTextAlignment(alignment)
        .lineLimit(4)
        .focused($isDraftFocused)
        .onSubmit { commitEditedDraft() }
        .onExitCommand { cancelEditing() }
        .onChange(of: isDraftFocused) { _, focused in
          if !focused && content.isEditable { commitEditedDraft() }
        }
        .onAppear { isDraftFocused = true }
    } else {
      switch settings.longDraftStyle {
      case .tailOnly:
        Text(content.text)
          .lineLimit(1)
          .truncationMode(.head)
          .onTapGesture(count: 2) { enterEditMode() }
      case .growDown:
        Text(content.text)
          .lineLimit(4)
          .multilineTextAlignment(alignment)
          .onTapGesture(count: 2) { enterEditMode() }
      case .shrinkToFit:
        Text(content.text)
          .lineLimit(1)
          .truncationMode(.head)
          .minimumScaleFactor(0.55)
          .onTapGesture(count: 2) { enterEditMode() }
      }
    }
  }

  private func enterEditMode() {
    content.preEditText = content.text
    stage?.acceptsMouse = true
    content.isEditable = true
    isDraftFocused = true
  }

  private func commitEditedDraft() {
    guard content.isEditable else { return }
    let edited = content.text
    let baseline = content.preEditText
    isDraftFocused = false
    content.isEditable = false
    content.preEditText = ""
    if edited.trimmingCharacters(in: .whitespacesAndNewlines) != baseline.trimmingCharacters(in: .whitespacesAndNewlines) {
      content.onEdited?(edited)
    }
  }

  private func cancelEditing() {
    guard content.isEditable else { return }
    isDraftFocused = false
    content.text = content.preEditText
    content.preEditText = ""
    content.isEditable = false
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

