# Talkify design reference

Written for a design tool that has never seen this codebase. Every number here
was read out of the shipping source, not remembered. File and line references
point at the source of truth if something needs checking.

Talkify is a menu-bar-only macOS dictation app. It has no Dock icon, no main
window, and no document model. Its entire visible surface is three things: a
black island that descends from the MacBook notch, a ghost icon in the menu
bar, and a dark modal Settings window.

## Read in this order

| File | What it covers |
| --- | --- |
| `design-system.md` | Color, type, spacing, radius, elevation, contrast |
| `hud-anatomy.md` | The notch island: geometry, bands, states, hard rules |
| `motion.md` | Every animation with its real spring and duration |
| `voice-visuals.md` | The three voice visuals and their palettes |
| `settings-ui.md` | The Settings modal and its component set |
| `FEATURE.md` | **Drop Transcription** — the feature being designed |

If you are designing the Drop Transcription card, read `FEATURE.md` last but
treat it as the brief. The other five files exist so the new surface looks
like it was always part of the app.

## The one-paragraph version of the aesthetic

Hardware black, not dark gray. The island is `Color.black` because it pretends
to be an extension of the MacBook's display housing, and any lighter value
breaks the illusion on a real notched Mac. Settings is near-black with barely
lifted cards. There is exactly one accent color, a blue, and it is used for
selection and interactive tint only. Color that carries meaning belongs to the
voice visuals, which the user picks. Everything else is white at low opacity.

Motion is fast and mostly bounce-free. Springs run 0.24s to 0.45s. The one
place bounce is allowed is scale anchored at the top edge, never position,
for a reason explained in `motion.md` that a designer needs to know before
proposing anything that moves.

## Conventions in these documents

Numbers written as `540 * scale` are multiplied by the user's HUD size, a
setting from 0.6 to 1.0 in 0.05 steps. Numbers written bare do not scale.
Which is which is a real design decision, not an oversight — see
`hud-anatomy.md`.

Colors are given as the source's sRGB components with a hex approximation.
The components are authoritative.
