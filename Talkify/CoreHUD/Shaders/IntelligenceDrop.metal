#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

/// Polynomial smooth minimum: two shapes closer than `k` grow a neck between
/// them, and the neck thins and snaps as they part. k = 0 is a plain union.
static float smoothUnion(float a, float b, float k) {
  if (k < 0.001) return min(a, b);
  float h = max(k - abs(a - b), 0.0) / k;
  return min(a, b) - h * h * k * 0.25;
}

/// Intelligence's orb as a liquid drop. The layer is the orb's moving mesh
/// gradient; this keeps only what lies inside a smooth union of the orb and a
/// bead under the housing, so on session start the orb drips out of the notch
/// and pinches off, and on session end it flows back in. Distances are signed
/// and in points, so the edge stays sharp at any HUD size: `pixel` is one
/// device pixel, the width of the anti-aliased edge.
[[ stitchable ]] half4 intelligenceDrop(
  float2 position,
  SwiftUI::Layer layer,
  float2 orbCenter,
  float orbRadius,
  float2 anchorCenter,
  float anchorRadius,
  float join,
  float pixel
) {
  float orb = length(position - orbCenter) - orbRadius;
  // A spent bead must not leave a point for the union to reach for.
  float anchor = anchorRadius > 0.01 ? length(position - anchorCenter) - anchorRadius : 1e4;
  float distance = smoothUnion(orb, anchor, join);
  float coverage = clamp(0.5 - distance / pixel, 0.0, 1.0);
  return layer.sample(position) * coverage;
}
