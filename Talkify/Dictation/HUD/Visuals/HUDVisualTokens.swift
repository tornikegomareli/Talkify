import SwiftUI

/// Tokens shared across the HUD's voice visuals.
enum HUDVisualTokens {
  /// The dead-microphone state's motionless amber (CONTEXT.md: a dead
  /// microphone must look different from silence). The waveform-family
  /// visuals keep their own dimmer orange variants, tuned per visual
  /// during feel tests.
  static let deadMicAmber = Color(red: 1.0, green: 0.6, blue: 0.16)

  /// The Chart Line treatment's metallic silver: white body cooling into a
  /// faint blue-gray at the ends — the edge glow's palette, no saturated
  /// hues. Shared so every Chart Line is recognisably one treatment.
  static let chartLineSilver = LinearGradient(
    colors: [
      Color(red: 0.68, green: 0.74, blue: 0.88).opacity(0.85),
      .white,
      Color(red: 0.82, green: 0.86, blue: 0.95),
      .white,
      Color(red: 0.68, green: 0.74, blue: 0.88).opacity(0.85),
    ],
    startPoint: .leading,
    endPoint: .trailing
  )
}
