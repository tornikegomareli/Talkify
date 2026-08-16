import SwiftUI
import Testing

@testable import Talkify

/// The warm-up names shader functions and their argument lists by hand. If a
/// name or an argument count drifts from the Metal source, `compile` throws —
/// which is the whole point of asserting it here rather than discovering a
/// silent no-op that leaves the stutter in place.
@Suite("Shader warm-up")
struct HUDShaderWarmUpTests {
  @Test func everyHUDShaderCompiles() async throws {
    for (shader, usage) in HUDShaderWarmUp.shadersForTesting {
      try await shader.compile(as: usage)
    }
  }
}
