/// What lives inside the Edge Glow's shape while listening, a Settings pick.
enum HUDGlowCenterStyle: String, CaseIterable {
    /// The compute-pipeline particle cloud chasing the beam's sweeping
    /// origin (HUDParticleCloudView).
    case particles = "Particles"
    /// Prototype under feel test: the rotating Siri orb (GetStream artwork,
    /// unlicensed — see LICENSE-ARTWORK.txt) breathing with the voice.
    case siriOrb = "Siri Orb"
    /// Prototype under feel test: the Siri Wave waveform style rendered in
    /// the band inside the sweeping beam.
    case siriWave = "Siri Wave"
}
