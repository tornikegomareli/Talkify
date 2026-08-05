#include <metal_stdlib>
using namespace metal;

/// Premium edge glow: a comet with a hot silver head and a long fading tail
/// traveling the HUD's open silhouette (down the left flank, across the
/// bottom, up to the notch — never the hidden top edge).
///
/// Rendered as a signed-distance glow: every pixel finds its distance to the
/// path and its position along it (arc length), the comet profile shapes
/// brightness along the path, and two inverse-power falloffs make the bloom —
/// a tight white-hot core and a wide cool halo, like light on glass.
///
/// `shapeRect` is the shape's frame inside the (larger) view so the halo has
/// room to spill outside the border. `alive` = 0 renders a static amber
/// outline (dead microphone ≠ silence).

struct PathPoint {
    float dist;   // distance from pixel to the path
    float s;      // arc position at the nearest point, 0…1
};

static PathPoint nearestOnU(float2 p, float w, float h, float r) {
    float pi = 3.14159265;
    float L1 = h - r;          // left flank
    float A = pi * r / 2.0;    // each corner arc
    float L2 = w - 2.0 * r;    // bottom run
    float total = 2.0 * L1 + 2.0 * A + L2;

    PathPoint best;
    best.dist = 1e6;
    best.s = 0.0;

    // Left flank: x = 0, y in 0…h-r (s grows downward).
    {
        float y = clamp(p.y, 0.0, L1);
        float d = length(p - float2(0.0, y));
        if (d < best.dist) { best.dist = d; best.s = y / total; }
    }
    // Bottom-left arc, center (r, h-r).
    {
        float2 c = float2(r, h - r);
        float2 v = p - c;
        float ang = atan2(v.y, v.x);              // -pi…pi, 0 = +x
        float a = clamp(ang, pi / 2.0, pi);       // 180° (left) … 90° (down)
        float2 onArc = c + r * float2(cos(a), sin(a));
        float d = length(p - onArc);
        if (d < best.dist) {
            best.dist = d;
            best.s = (L1 + (pi - a) * r) / total;
        }
    }
    // Bottom run: y = h, x in r…w-r.
    {
        float x = clamp(p.x, r, w - r);
        float d = length(p - float2(x, h));
        if (d < best.dist) {
            best.dist = d;
            best.s = (L1 + A + (x - r)) / total;
        }
    }
    // Bottom-right arc, center (w-r, h-r).
    {
        float2 c = float2(w - r, h - r);
        float2 v = p - c;
        float ang = atan2(v.y, v.x);
        float a = clamp(ang, 0.0, pi / 2.0);      // 90° (down) … 0° (right)
        float2 onArc = c + r * float2(cos(a), sin(a));
        float d = length(p - onArc);
        if (d < best.dist) {
            best.dist = d;
            best.s = (L1 + A + L2 + (pi / 2.0 - a) * r) / total;
        }
    }
    // Right flank: x = w, y in 0…h-r (s grows upward).
    {
        float y = clamp(p.y, 0.0, L1);
        float d = length(p - float2(w, y));
        if (d < best.dist) {
            best.dist = d;
            best.s = (L1 + 2.0 * A + L2 + (L1 - y)) / total;
        }
    }
    return best;
}

[[ stitchable ]] half4 edgeGlow(
    float2 position,
    half4 currentColor,
    float2 size,
    float4 shapeRect,   // x, y, width, height of the shape inside the view
    float cornerRadius,
    float time,
    float level,
    float alive,
    float pulseAge   // seconds since the last syllable onset; large = none
) {
    float2 p = position - shapeRect.xy;
    float w = shapeRect.z;
    float h = shapeRect.w;
    float r = min(cornerRadius, h / 2.0);

    PathPoint pt = nearestOnU(p, w, h, r);
    float d = max(pt.dist, 0.35);

    if (alive < 0.5) {
        // Dead microphone: motionless amber outline.
        float glow = 0.5 / (d * d) + 0.06 / d;
        glow = min(glow, 1.0);
        return half4(half3(1.0, 0.6, 0.16) * half(glow * 0.6), half(glow * 0.65));
    }

    // The head ping-pongs corner → notch → corner, easing at the turnarounds.
    float phase = fmod(time / 2.6, 2.0);
    float lin = phase < 1.0 ? phase : 2.0 - phase;
    float head = lin * lin * (3.0 - 2.0 * lin);   // smoothstep easing
    float dir = phase < 1.0 ? 1.0 : -1.0;         // travel direction

    // Comet profile along the path: sharp front, long exponential tail.
    float ds = (pt.s - head) * dir;               // + ahead of the head
    float front = exp(-ds * ds / 0.0006) * step(0.0, ds);
    float tail = exp(ds / 0.16) * step(0.0, -ds);
    float profile = max(front, tail);

    // Voice is the main act: the whole outline swells with the level (squared
    // so silence stays calm and speech pops), and the comet rides on top as
    // the motion carrier. Silence keeps just enough light to read alive.
    float voice = level * level;
    float brightness = 0.25 + 0.75 * level;
    float base = 0.03 + 0.65 * voice;
    float intensity = base + profile * brightness;

    // Two-scale bloom: white-hot core, wide halo. Both widen as you speak.
    float core = (1.0 + 2.5 * voice) / (d * d);
    float halo = (0.14 + 0.55 * voice) / d;
    float glow = intensity * min(core + halo, 3.5);

    // Syllable pulse: the whole border flashes and a soft ring of light
    // ripples outward from it, both dying within ~half a second.
    float flash = exp(-pulseAge * 6.0);
    glow *= 1.0 + 1.4 * flash;
    float ringRadius = 3.0 + pulseAge * 110.0;
    float ring = exp(-pow(pt.dist - ringRadius, 2.0) / 40.0) * exp(-pulseAge * 4.0);
    glow += ring * 0.45 * (0.4 + 0.6 * level);

    // Silver treatment: the hot core is pure white, the falloff cools into a
    // faint blue-violet fringe like light bleeding on glass.
    half3 white = half3(1.0, 1.0, 1.0);
    half3 fringe = half3(0.62, 0.72, 1.0);
    float heat = clamp(glow * 0.8, 0.0, 1.0);
    half3 tint = mix(fringe, white, half(heat * heat));

    half a = half(clamp(glow, 0.0, 1.0));
    return half4(tint * half(min(glow, 1.6)) * a, a);
}
