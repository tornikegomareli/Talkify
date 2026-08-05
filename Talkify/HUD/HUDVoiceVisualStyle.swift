/// The voice-reactive visual shown while listening. CONTEXT.md flags this as
/// undecided; both variants stay selectable until the pick is made by feel.
/// Reduce Motion overrides either with a quiet level meter.
enum HUDVoiceVisualStyle: String, CaseIterable {
    /// A Metal shader waveform that fills the HUD and replaces the draft
    /// text entirely while listening.
    case waveform = "Waveform"
    /// An Aurora glow hugging the shape's edge, draft text in the middle,
    /// intensity following the voice.
    case glow = "Edge Glow"
}
