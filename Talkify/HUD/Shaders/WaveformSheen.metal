#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

/// WWDC26-style treatment applied over the drawn waveform pixels:
/// - chromatic aberration: red and blue sampled at slightly offset positions,
///   so shape edges fringe into rainbow like the metallic logo
/// - a metallic specular band sweeping across, easing at the turnarounds
/// - cheap bloom: neighboring samples folded in so bright pixels bleed
///
/// `level` (0-1) breathes the aberration and sweep strength with the voice.
[[ stitchable ]] half4 waveformSheen(
  float2 position,
  SwiftUI::Layer layer,
  float2 size,
  float time,
  float level
) {
  float2 uv = position;

  // Fringe grows from the horizontal center outward and with the voice.
  float centered = (uv.x / max(size.x, 1.0)) * 2.0 - 1.0;
  float aberration = (1.0 + 2.2 * level) * centered;

  half4 base = layer.sample(uv);
  half r = layer.sample(uv + float2(aberration, 0.0)).r;
  half b = layer.sample(uv - float2(aberration, 0.0)).b;
  half4 color = half4(r, base.g, b, base.a);

  // Bloom: four taps folded in, so bright bars halo softly.
  half4 spread = layer.sample(uv + float2(3.0, 0.0))
        + layer.sample(uv - float2(3.0, 0.0))
        + layer.sample(uv + float2(0.0, 3.0))
        + layer.sample(uv - float2(0.0, 3.0));
  color += spread * half(0.12 + 0.10 * level);

  // Metallic sweep: a soft specular band ping-ponging across the strip.
  float phase = fmod(time / 2.8, 2.0);
  float lin = phase < 1.0 ? phase : 2.0 - phase;
  float sweep = lin * lin * (3.0 - 2.0 * lin);
  float x = uv.x / max(size.x, 1.0);
  float band = exp(-pow((x - sweep) * 7.0, 2.0));
  color.rgb *= half(1.0 + (0.55 + 0.45 * level) * band);

  return min(color, half4(1.0));
}
