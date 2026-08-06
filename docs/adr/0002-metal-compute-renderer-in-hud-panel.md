# Metal compute renderer inside the HUD panel

The Edge Glow particle cloud runs a Metal compute pipeline (an `MTKView` hosted through `NSViewRepresentable`) inside the click-through HUD panel, next to the SwiftUI-only shader effects (`colorEffect`, `layerEffect`). SwiftUI's shader hooks cannot express a particle system — they transform existing pixels per frame but cannot carry mutable state (position, lifespan) across frames; a compute kernel writing into an `MTLBuffer` can. We kept the SwiftUI hooks for the border glow and the ripple, where they are simpler and cheaper.

## Consequences

- Transparency is the macOS shape of the problem: the panel is non-opaque, so the `MTKView` needs `framebufferOnly = false` (the kernel writes straight into the drawable), a clear `clearColor`, and `layer?.isOpaque = false` on the backing `CAMetalLayer` — there is no `backgroundColor` to clear as on iOS.
- Pause policy: at session-ramp zero the view sets `isPaused = true` after one forced clearing draw, so an idle HUD costs no GPU and never freezes stale motes on screen.
- Isolation: `MTKViewDelegate` is main-actor-isolated in the macOS 26 SDK, so `ParticleRenderer` is a plain `@MainActor` class — no locks, no `@preconcurrency`.
- The Swift structs mirror the Metal structs member-for-member; SIMD alignment makes the order load-bearing, and `HUDParticleLayoutTests` pins the strides and offsets so a reorder fails a test instead of corrupting the buffer silently.
- Fail-soft: if Metal setup fails, the cloud draws nothing. A decorative effect must never crash a menu-bar app.
