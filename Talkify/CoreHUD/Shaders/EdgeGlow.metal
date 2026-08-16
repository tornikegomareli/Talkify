#include <metal_stdlib>
using namespace metal;

/// The Edge Glow origin mask — the `glow` function from the article's gist.
/// The beam itself is SwiftUI: HUDEdgeGlowView strokes the silhouette with a
/// palette gradient and two blurred copies (the gist's GlowModifier). This
/// shader only decides how much of that picture shows: intensity falls off
/// with normalized distance from the origin, spreads outward as the session
/// ramp grows, and scales with the voice-driven amplitude.
[[ stitchable ]] half4 edgeGlow(
  float2 position,
  half4 color,
  float2 origin,
  float2 size,
  float amplitude,    // voice-driven; the gist uses a constant 3.0
  float progress      // session ramp, 0…1
) {
  float2 uvPosition = position / size;
  float2 uvOrigin = origin / size;

  float distance = length(uvPosition - uvOrigin);

  float intensity = smoothstep(0.0, 1.0, progress)
    * exp(-distance * distance)
    * amplitude;
  intensity *= smoothstep(0.0, 1.0, 1.0 - distance / max(progress, 1e-3));

  return color * intensity;
}
