/// The voice-reactive visual shown while listening. Both variants ship,
/// user-selectable from Settings; both replace the draft text while
/// listening. Reduce Motion overrides either with a quiet level meter.
enum HUDVoiceVisualStyle: String, CaseIterable {
    /// A Metal shader waveform that fills the HUD's visual band.
    case waveform = "Waveform"
    /// An origin glow hugging the shape's edge: it blooms out of the notch
    /// housing on session start, breathes with the voice, and drains back
    /// when the session ends.
    case glow = "Edge Glow"
    /// Prototype under feel test: the rotating Siri orb (GetStream artwork,
    /// unlicensed — see LICENSE-ARTWORK.txt) breathing with the voice.
    case siriOrb = "Siri Orb"
}
