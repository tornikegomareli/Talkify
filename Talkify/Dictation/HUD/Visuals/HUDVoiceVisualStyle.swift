/// The voice-reactive visual shown while listening, user-selectable from
/// Settings. Waveform and Edge Glow replace the draft text; Compact and
/// Edge Glow + Draft keep it. Reduce Motion overrides all of them with a
/// quiet level meter.
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

  /// Compact and Edge Glow + Draft are built around the live draft, so a
  /// placeholder would be words nobody spoke.
  var showsDraftWhileListening: Bool {
    self == .compact || self == .glowDraft
  }

  /// The beam, start ripple, shaping caption, and status-ghost accent.
  var usesEdgeGlow: Bool {
    self == .glow || self == .glowDraft
  }
}
