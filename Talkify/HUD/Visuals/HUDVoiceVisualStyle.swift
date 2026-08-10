/// The voice-reactive visual shown while listening, user-selectable from
/// Settings. Waveform and Edge Glow replace the draft text unless the Live
/// draft pick keeps it; Compact is built around the draft text. Reduce
/// Motion overrides all of them with a quiet level meter.
enum HUDVoiceVisualStyle: String, CaseIterable {
  /// A Metal shader waveform that fills the HUD's visual band.
  case waveform = "Waveform"
  /// An origin glow hugging the shape's edge: it blooms out of the notch
  /// housing on session start, breathes with the voice, and drains back
  /// when the session ends. Its center content is a separate pick
  /// (HUDGlowCenterStyle).
  case glow = "Edge Glow"
  /// The Dynamic Island caption look: a small voice indicator beside the
  /// live draft text inside the shape (HUDCompactIndicatorView); the shape
  /// grows with the draft.
  case compact = "Compact"
}
