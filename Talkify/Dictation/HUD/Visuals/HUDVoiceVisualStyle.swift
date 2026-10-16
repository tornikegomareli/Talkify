/// The voice-reactive visual shown while listening, user-selectable from
/// Settings. Waveform and Edge Glow replace the draft text; Compact,
/// Edge Glow + Draft and Flying Ghost keep it. Reduce Motion overrides all of
/// them with a quiet level meter.
enum HUDVoiceVisualStyle: String, CaseIterable {
  /// A Metal shader waveform that fills the HUD's visual band.
  case waveform = "Waveform"
  /// An origin glow hugging the shape's edge: it blooms out of the notch
  /// housing on session start, breathes with the voice, and drains back
  /// when the session ends. Its center content is a separate pick
  /// (HUDGlowCenterStyle).
  case glow = "Edge Glow"
  /// Centered recent-word live draft and Edge Glow on the silhouette. No
  /// Chart Line, five-bar indicator, particle cloud, or orb. The concert
  /// waveform styles stay on Waveform.
  case glowDraft = "Edge Glow + Draft"
  /// The Dynamic Island caption look: a small voice indicator beside the
  /// live draft text inside the shape (HUDCompactIndicatorView); the shape
  /// grows with the draft.
  case compact = "Compact"
  /// Edge Glow + Draft's island, with Talkify's ghost: it flies out of the
  /// notch on session start, eats the live draft as it arrives, and flies
  /// home when speech ends. A rim of the palette turns inside the shape and
  /// the words take the palette too. Shipped in 0.9.0 as "Intelligence",
  /// which AppSettings still reads as this.
  case flyingGhost = "Flying Ghost"

  /// Compact and Edge Glow + Draft are built around the live draft, so a
  /// placeholder would be words nobody spoke.
  var showsDraftWhileListening: Bool {
    self == .compact || self == .glowDraft || self == .flyingGhost
  }

  /// The beam, start ripple, shaping caption, and status-ghost accent.
  var usesEdgeGlow: Bool {
    self == .glow || self == .glowDraft || self == .flyingGhost
  }

  /// The centered recent-word line on its hanging stage, in place of the
  /// draft band and its long-draft behaviors.
  var showsRecentDraftLine: Bool {
    self == .glowDraft || self == .flyingGhost
  }
}
