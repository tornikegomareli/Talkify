import Testing
@testable import Talkify

/// Pins the Swift-side particle structs to the layout the Metal kernels
/// expect (ParticleCloud.metal). SIMD2/SIMD4 alignment makes member order
/// load-bearing: reordering compiles fine and corrupts the buffer silently.
struct HUDParticleLayoutTests {
    @Test func particleMatchesTheMetalLayout() {
        #expect(MemoryLayout<ParticleRenderer.Particle>.stride == 48)
        #expect(MemoryLayout<ParticleRenderer.Particle>.offset(of: \.color) == 0)
        #expect(MemoryLayout<ParticleRenderer.Particle>.offset(of: \.radius) == 16)
        #expect(MemoryLayout<ParticleRenderer.Particle>.offset(of: \.lifespan) == 20)
        #expect(MemoryLayout<ParticleRenderer.Particle>.offset(of: \.position) == 24)
        #expect(MemoryLayout<ParticleRenderer.Particle>.offset(of: \.velocity) == 32)
    }

    @Test func cloudInfoMatchesTheMetalLayout() {
        #expect(MemoryLayout<ParticleRenderer.CloudInfo>.stride == 16)
        #expect(MemoryLayout<ParticleRenderer.CloudInfo>.offset(of: \.center) == 0)
        #expect(MemoryLayout<ParticleRenderer.CloudInfo>.offset(of: \.progress) == 8)
    }
}
