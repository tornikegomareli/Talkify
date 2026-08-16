/// How the HUD enters and leaves. All styles keep the shape's top edge glued
/// to the screen edge: bounce is expressed in scale anchored at the top, never
/// in position, so overshoot can't open a gap above the shape.
enum HUDRevealStyle: String, CaseIterable {
  /// Slides down from outside the screen edge. No bounce — a position
  /// overshoot would detach the shape from the edge.
  case slide = "Slide"
  /// Unrolls downward out of the housing, stretching past its height and
  /// settling back. The bounciest of the set.
  case unfurl = "Unfurl"
  /// Inflates from the housing while fading in, with a soft overshoot.
  case bloom = "Bloom"
  /// Barely moves: fades in while drifting down the last few points.
  /// The most understated.
  case drift = "Drift"
}
