import SwiftUI

/// Tokens shared across the HUD's voice visuals.
enum HUDVisualTokens {
  /// The dead-microphone state's motionless amber (CONTEXT.md: a dead
  /// microphone must look different from silence). The waveform-family
  /// visuals keep their own dimmer orange variants, tuned per visual
  /// during feel tests.
  static let deadMicAmber = Color(red: 1.0, green: 0.6, blue: 0.16)
}
