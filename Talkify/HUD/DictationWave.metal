#include <metal_stdlib>
using namespace metal;

/// The waveform voice visual: layered Siri-style sinusoids rendered as
/// additive glow lines on the black housing. `level` (0-1) drives amplitude;
/// `alive` = 0 freezes everything into a static amber line so a dead
/// microphone reads differently from silence, which keeps a small breathing
/// baseline instead.
[[ stitchable ]] half4 dictationWave(
    float2 position,
    half4 currentColor,
    float2 size,
    float time,
    float level,
    float alive
) {
    float2 uv = position / size;
    float x = uv.x * 2.0 - 1.0;   // -1 … 1 across the band
    float y = 1.0 - uv.y * 2.0;   // +1 top … -1 bottom

    if (alive < 0.5) {
        // Dead microphone: one motionless amber line.
        float d = max(abs(y), 0.03);
        float glow = 0.0016 / (d * d);
        glow = min(glow, 1.0);
        return half4(half3(1.0, 0.62, 0.18) * half(glow * 0.55), half(glow * 0.6));
    }

    // Edge attenuation pins the wave to the band's ends.
    float att = pow(1.0 / (1.0 + 3.5 * x * x), 2.0);
    // Silence keeps a visible breathing baseline (CONTEXT: silence != dead).
    float amp = max(level, 0.05 + 0.025 * sin(time * 2.1));

    half3 acc = half3(0.0);
    for (int i = 0; i < 5; i++) {
        float fi = float(i);
        float layerAmp = amp * att * (1.0 - 0.15 * fi);
        // Each layer wobbles at its own pace so crossings shimmer.
        float carrier = sin(3.14159 * x * (1.2 + 0.5 * fi) + time * (1.7 + 0.55 * fi) + fi * 2.3);
        float swell = sin(time * (0.9 + 0.27 * fi) + fi * 1.4);
        float wave = 1.5 * layerAmp * carrier * swell;

        float d = abs(y - wave);
        float glow = 0.0042 / max(d * d, 0.00042);
        glow = min(glow, 2.4);

        // Hue drifts across the band per layer: cyan -> violet -> magenta.
        float hueT = clamp(uv.x + 0.14 * sin(time * 0.55 + fi * 0.9), 0.0, 1.0);
        half3 cyan = half3(0.30, 0.78, 1.00);
        half3 violet = half3(0.62, 0.45, 1.00);
        half3 magenta = half3(1.00, 0.42, 0.82);
        half3 tint = hueT < 0.5
            ? mix(cyan, violet, half(hueT * 2.0))
            : mix(violet, magenta, half(hueT * 2.0 - 1.0));

        acc += tint * half(glow) * half(0.26);
    }

    half alpha = clamp(max(acc.r, max(acc.g, acc.b)), half(0.0), half(1.0));
    return half4(min(acc, half3(1.0)), alpha);
}
