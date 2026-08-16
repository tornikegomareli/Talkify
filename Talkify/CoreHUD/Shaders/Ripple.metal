#include <SwiftUI/SwiftUI.h>
#include <metal_stdlib>

using namespace metal;

/// The WWDC24 "Create custom visual effects with SwiftUI" ripple: a single
/// wave expanding from `origin`, displacing pixels along the radial direction
/// and brightening them by the ripple amount. On the HUD it rolls across the
/// black housing once, at session start.
[[ stitchable ]] half4 ripple(
  float2 position,
  SwiftUI::Layer layer,
  float2 origin,
  float time,
  float amplitude,
  float frequency,
  float decay,
  float speed
) {
  // The distance of the current pixel position from `origin`.
  float distance = length(position - origin);

  // The amount of time it takes for the ripple to arrive at the current
  // pixel position; clamp so the wave hasn't arrived yet at far pixels.
  float delay = distance / speed;
  time = max(0.0, time - delay);

  // A sine wave scaled by an exponential decay.
  float rippleAmount = amplitude * sin(frequency * time) * exp(-decay * time);

  // Displace the sampled pixel toward or away from `origin`.
  float2 direction = normalize(position - origin);
  float2 newPosition = position + rippleAmount * direction;

  half4 color = layer.sample(newPosition);

  // Lighten or darken based on the ripple amount and the pixel's alpha.
  color.rgb += (rippleAmount / amplitude) * color.a;

  return color;
}
