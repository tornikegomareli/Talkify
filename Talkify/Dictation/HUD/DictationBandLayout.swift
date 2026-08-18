import CoreGraphics

/// What the dictation shell's bands show for a session state — a pure
/// decision, so the review-context rules are pinned without a window.
///
/// The rule that a bug was found against lives here on purpose: once the
/// draft is under review it never disappears, not even while a replacement
/// round is listening, and no waveform or glow band (or level meter under
/// Reduce Motion) may replace it. The compact voice indicator beside the
/// text is the most a reviewing replacement round gets.
struct DictationBandLayout: Equatable {
  /// Whether the bands stay as a listening session laid them out. Held
  /// through the retract so the shape never resizes while it slides away.
  let keepsVisualLayout: Bool
  /// Height of the voice visual's band below the housing, 0 when the
  /// current state shows no visual band.
  let visualBandHeight: CGFloat
  /// Whether the draft text band is present at all.
  let showsTextBand: Bool
  /// Whether the text band renders the Compact layout: the voice indicator
  /// beside a leading-aligned draft.
  let showsCompactBand: Bool
  /// A replacement round listening under a held draft: the voice visual
  /// must not take over, so its overlays stand down too.
  let isReplacementRoundListening: Bool

  init(
    showsVoiceVisual: Bool,
    isDismissing: Bool,
    isReviewing: Bool,
    reduceMotion: Bool,
    voiceVisual: HUDVoiceVisualStyle,
    levelMeterBandHeight: CGFloat,
    waveBandHeight: CGFloat
  ) {
    let keepsVisualLayout = showsVoiceVisual || isDismissing
    self.keepsVisualLayout = keepsVisualLayout
    isReplacementRoundListening = isReviewing && showsVoiceVisual

    if isReviewing {
      // The draft never disappears while under review: the text band
      // always shows, and no waveform/glow (or level meter) band replaces
      // it. A listening replacement round may show the compact indicator
      // beside the text.
      visualBandHeight = 0
      showsTextBand = true
      showsCompactBand = isReplacementRoundListening && !reduceMotion
    } else if keepsVisualLayout, !reduceMotion, voiceVisual != .compact {
      // Waveform and Edge Glow replace the draft text entirely while
      // listening.
      visualBandHeight = waveBandHeight
      showsTextBand = false
      showsCompactBand = false
    } else if reduceMotion {
      // Reduce Motion stands in for every visual with the quiet level
      // meter in its slim band; the draft text always shows.
      visualBandHeight = keepsVisualLayout ? levelMeterBandHeight : 0
      showsTextBand = true
      showsCompactBand = false
    } else {
      // Compact is built around the draft, and every idle state shows the
      // text band on its own.
      visualBandHeight = 0
      showsTextBand = true
      showsCompactBand = voiceVisual == .compact
    }
  }
}
