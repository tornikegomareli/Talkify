#include <metal_stdlib>
using namespace metal;

/// Premium edge glow: an origin glow that blooms out of the notch housing and
/// spreads along the HUD's open silhouette (down the left flank, across the
/// bottom, up to the notch — never the hidden top edge), then drains back when
/// the session ends.
///
/// Rendered as a signed-distance glow: every pixel finds its distance to the
/// path and its position along it (arc length). The origin-glow formula
/// (smoothstep(progress) · exp(-d²) · amplitude) shapes brightness along the
/// arc from the origin outward, and two gaussians make the beam perpendicular
/// to the path — a hot ~3pt core inside a wide ~16pt halo, the profile of the
/// article's stroked-and-blurred border rather than a hairline. `progress` is
/// the session ramp (0→1 on start, 1→0 on end) and `amplitude` follows the
/// live microphone level.
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
    float originS,      // arc position of the glow origin, 0.5 = bottom-center
    float progress,     // session ramp, 0…1
    float amplitude,    // voice-driven intensity
    float alive
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

    // Arc distance from the origin: 0 at the origin (bottom-center of the
    // housing), 1 at the flank tips beside the notch.
    float dAlong = abs(pt.s - originS) * 2.0;

    // The origin-glow formula runs along the arc: brightness falls off with
    // arc distance, ramps with the session, and breathes with the voice. The
    // second smoothstep spreads the reach outward as progress grows, so the
    // light visibly travels from the origin around the rim.
    float spread = smoothstep(0.0, 1.0, progress)
        * exp(-dAlong * dAlong)
        * amplitude;
    spread *= smoothstep(0.0, 1.0, 1.0 - dAlong / max(progress, 1e-3));

    // The beam perpendicular to the path: a blurred-stroke profile, not a
    // hairline. A hot gaussian core (σ ≈ 3pt) rides inside a wide soft halo
    // (σ ≈ 16pt) that spills to both sides of the border.
    float core = exp(-d * d / 18.0);
    float halo = 0.45 * exp(-d * d / 260.0);
    float glow = spread * (core + halo) * 1.6;

    // Silver treatment: the hot core is pure white, the falloff cools into a
    // faint blue-violet fringe like light bleeding on glass.
    half3 white = half3(1.0, 1.0, 1.0);
    half3 fringe = half3(0.62, 0.72, 1.0);
    float heat = clamp(glow * 0.8, 0.0, 1.0);
    half3 tint = mix(fringe, white, half(heat * heat));

    half a = half(clamp(glow, 0.0, 1.0));
    return half4(tint * half(min(glow, 1.6)) * a, a);
}
