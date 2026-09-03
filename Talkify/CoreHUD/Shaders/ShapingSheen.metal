#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

/// Tints the shaping label's glyphs with the Edge Glow palette and moves the
/// color through them, so the line naming the prompt reads as part of the same
/// visual as the beam rather than as chrome sitting under it.
///
/// The three colors come from the palette the user picked, so this follows the
/// Settings choice instead of carrying a palette of its own.
///
/// `level` (0-1) breathes it with the voice: the ramp travels faster, the
/// specular band brightens, and the whole line lifts out of its resting dim.
/// At silence it settles rather than going dark, because a label that
/// disappears between words reads as a glitch.
[[ stitchable ]] half4 shapingSheen(
  float2 position,
  SwiftUI::Layer layer,
  float2 size,
  float time,
  float level,
  half4 colorA,
  half4 colorB,
  half4 colorC
) {
  half4 base = layer.sample(position);
  // Glyph coverage is the only thing kept from the drawn pixels: the label is
  // rendered white, so its alpha is the mask and its color is discarded.
  half coverage = base.a;
  if (coverage <= 0.001h) {
    return half4(0.0h);
  }

  float x = position.x / max(size.x, 1.0);
  // The ramp travels leftward through the glyphs, and louder speech carries it
  // faster. 0.09 keeps it a drift at silence rather than a stall.
  float travel = time * (0.09 + 0.5 * level);
  float ramp = fract(x * 0.85 - travel);

  // Three stops across the ramp, wrapping back to the first so the seam never
  // shows: A to B, B to C, C back to A.
  half4 color;
  if (ramp < 0.3333) {
    color = mix(colorA, colorB, half(smoothstep(0.0, 0.3333, ramp)));
  } else if (ramp < 0.6667) {
    color = mix(colorB, colorC, half(smoothstep(0.3333, 0.6667, ramp)));
  } else {
    color = mix(colorC, colorA, half(smoothstep(0.6667, 1.0, ramp)));
  }

  // A specular band sweeping the other way, the same treatment the waveform
  // gets, so both visuals catch light the same way.
  float phase = fmod(time / 2.4, 2.0);
  float lin = phase < 1.0 ? phase : 2.0 - phase;
  float sweep = lin * lin * (3.0 - 2.0 * lin);
  float band = exp(-pow((x - sweep) * 6.0, 2.0));
  color.rgb *= half(1.0 + (0.25 + 0.55 * level) * band);

  // Resting brightness, lifted by the voice. The label stays legible at
  // silence and never blows past white when both the band and a loud level
  // land on the same pixel.
  color.rgb = min(color.rgb * half(0.62 + 0.38 * level), half3(1.0h));

  return half4(color.rgb * coverage, coverage);
}
