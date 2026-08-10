import SwiftUI

/// Hosts the ripple shader (Ripple.metal): a single light wave rolling across
/// the housing from the glow origin, once, at session start. Part of the
/// Edge Glow visual — the shell applies it to the housing fill only when that
/// variant is selected, and disables it entirely outside the burst.
struct HUDRippleModifier: ViewModifier {
  /// How long one burst runs; elapsed time animates 0 → duration.
  nonisolated static let duration: TimeInterval = 1.2

  let origin: CGPoint
  let elapsedTime: TimeInterval
  let isEnabled: Bool

  func body(content: Content) -> some View {
    content.layerEffect(
      ShaderLibrary.ripple(
        .float2(origin),
        .float(elapsedTime),
        .float(3),      // amplitude, points of displacement
        .float(6),      // frequency
        .float(6),      // decay
        .float(1200)    // speed, pt/s — crosses the shape in ~0.45s
      ),
      maxSampleOffset: CGSize(width: 4, height: 4),
      isEnabled: isEnabled && elapsedTime > 0 && elapsedTime < Self.duration
    )
  }
}
