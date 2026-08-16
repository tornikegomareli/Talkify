# Voice visuals

Source: `Talkify/Dictation/HUD/Visuals/`, `Talkify/CoreHUD/Shaders/`.

The animated thing inside the island that reacts to the user's voice. Three
of them, user-selectable, default Waveform. Rendering is Metal for the heavy
ones (ADR-0002).

This document exists mostly so a new surface knows what visual language it is
joining, and what colors are already spoken for.

## The three

**Waveform** — a shader waveform filling the `64 * scale` visual band. Nine
sub-styles the user picks between: Article, Silver, Capsules, Chart Line
(default, a conveyor with metallic silver treatment), Chart Area, Dots,
Curve, Filled, and Siri Wave. It replaces the draft text entirely while
listening.

**Edge Glow** — light hugging the shape's open silhouette. Three parts: a
palette-gradient beam that blooms in from under the housing at session start,
sweeps the outline while listening, follows the voice in brightness and
stroke width, and drains back when the session ends; a one-shot ripple that
rolls across the housing at session start, displacing its pixels; and a
center element. The visual band stays empty here and acts as a stage, so the
silhouette has flanks for light to wrap around. Also replaces draft text.

**Compact** — a five-bar indicator beside leading-aligned live draft text,
after the iOS Dynamic Island caption look. Bars are 2.5pt wide capsules,
2.5pt apart, resting at 3pt and reaching about 14pt. This is the only visual
that shows the draft while listening, and the shape grows with the text.

Under Reduce Motion all three are replaced by a quiet level meter in the slim
`24 * scale` band, and the draft text always shows.

## Edge Glow palettes

Six, user-selectable, coloring the beam and particles together. Each also
carries one representative accent used to tint the menu bar ghost during a
session.

| Palette | Character | Status accent |
| --- | --- | --- |
| Spectrum | Blue → purple → red → mint → indigo → pink | `#8C80FF` |
| Silver | White through pale blue, metallic | `#BFCCFF` |
| Aurora | Mint, teal, green, cyan | `#33D999` |
| Sunset | Orange, red, pink, purple | `#FF734D` |
| Ocean | Blue, cyan, indigo, deep navy | `#3399FF` |
| Mono | Flat white | `#FFFFFF` |

Beam strokes are angular gradients swept a full turn. Particle clouds cycle
three colors drawn from the same palette.

The center of the Edge Glow is a separate pick: a particle cloud (default) or
a rotating orb. The orb ships behind a development flag only — its artwork is
unlicensed and cannot appear in a release.

## Color ownership

Palette colors belong to the voice visual. They never leak into Settings
chrome, the accent, or any other surface. If a new surface needs color, it
takes the fixed blue accent or white-at-an-opacity, not a palette.

The one reserved semantic color is `#FF9929` amber, which means the
microphone is dead. It is motionless by design — silence settles a visual to
rest, a dead microphone freezes it amber. Do not use amber for anything else
in the HUD.
