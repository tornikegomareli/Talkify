import SwiftUI

/// The measurements and colours every Drop Transcription surface draws from,
/// derived once from the session settings so the four state views take one
/// value instead of reaching into preferences apiece.
struct DropHUDStyle {
  let metrics: HUDMetrics
  /// The accent for glyphs, the peek bar, and the notice.
  ///
  /// The drop surfaces speak the voice visual's colour: Edge Glow lends its
  /// palette — the same hue the status ghost takes during a glow session, so
  /// one palette means one colour everywhere — and every other visual keeps
  /// the Talkify blue. Settings chrome is unaffected either way; the palette
  /// colours the HUD, never the app (CONTEXT.md).
  let accent: Color
  /// The receptive edge gets the palette's whole gradient rather than one hue
  /// of it: it is the one element long enough to show a palette off.
  let accentStroke: AnyShapeStyle

  var scale: CGFloat { metrics.scale }

  init(settings: DictationSessionSettings) {
    metrics = settings.hudMetrics
    accent = Color(nsColor: settings.dropAccent)
    accentStroke = settings.voiceVisual == .glow
      ? settings.glowPalette.stroke
      : AnyShapeStyle(SettingsTheme.accent)
  }

  /// The corner every inner panel shares — the well, the card.
  var innerRadius: CGFloat { 12 * scale }

  /// The transcript's icon. `text.document` over `doc.text`: same idea drawn
  /// with the current SF Symbols line weight, and it reads as a page of words
  /// rather than as a generic document at 20 points.
  nonisolated static let transcriptSymbol = "text.document"
}
