/// The voice-reactive visual shown while listening. CONTEXT.md flags this as
/// undecided; both variants stay selectable until the pick is made by feel.
/// Reduce Motion overrides either with a quiet level meter.
enum HUDVoiceVisualStyle: String, CaseIterable {
    /// A live waveform strip below the housing, driven by microphone level.
    case waveform = "Waveform"
    /// A glow hugging the shape's edge, draft text in the middle, intensity
    /// following the voice.
    case glow = "Edge Glow"

    /// Whether this visual occupies the band between housing and text.
    var usesVisualBand: Bool {
        self == .waveform
    }
}
