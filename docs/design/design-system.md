# Design system

Source of truth: `Talkify/Settings/Components/SettingsTheme.swift`,
`Talkify/Dictation/HUD/Visuals/HUDVisualTokens.swift`, and the views themselves. Talkify
has no central token file beyond those two — most values live at their point
of use, so this document collects them.

## Color

### Named tokens

| Token | sRGB | Hex | Used for |
| --- | --- | --- | --- |
| Accent | `0.36, 0.58, 1.00` | `#5C94FF` | Selection, slider tint, interactive emphasis |
| Settings background | `0.025, 0.027, 0.035` | `#060709` | The modal's content pane |
| Settings sidebar | `0.035, 0.038, 0.049` | `#090A0D` | Navigation rail |
| Settings card | `0.065, 0.069, 0.087` | `#111216` | Grouped row containers |
| Dead-mic amber | `1.00, 0.60, 0.16` | `#FF9929` | The motionless "microphone is dead" state |
| HUD fill | pure `Color.black` | `#000000` | The island |

The accent is fixed. A user's Edge Glow palette pick never recolors Settings
chrome or the island — the palettes belong to the voice visual alone.

### Everything else is white at an opacity

There are no gray tokens. Secondary content is white with an alpha, and the
alpha rises when the system's Increase Contrast setting is on.

| Role | Normal | Increase Contrast |
| --- | --- | --- |
| Card group title | `0.44` | `0.70` |
| Row description | `0.48` | `0.72` |
| Card border | `0.09` | `0.22` |
| Row separator | `0.07` | `0.16` |
| Slider readout | `0.62` | unchanged |
| Language tag text | `0.72` | unchanged |
| Language tag fill | `0.13` | unchanged |
| Button fill | `0.10` (pressed `0.18`) | unchanged |
| Button border | `0.12` | unchanged |

Anything new should follow the same ladder rather than introducing a gray.

## Typography

San Francisco throughout, via `.system`. No custom font, no display face.

| Element | Size | Weight | Notes |
| --- | --- | --- | --- |
| HUD draft text | `15 * scale` | Medium | Pure white |
| HUD language tag | `9 * scale` | Semibold | `.rounded` design, tracking `0.5` |
| Settings card title | `11` | Semibold | Tracking `0.6`, effectively an all-caps group label |
| Settings row title | `13` | Medium | |
| Settings row description | `.caption` | Regular | |
| Settings numeric readout | `12` | Medium | `monospacedDigit`, fixed 36pt width, trailing |
| Settings button | `12` | Semibold | |

Two rules worth keeping. Any number that changes while you watch it is
`monospacedDigit`, so it does not jitter. Small labels get tracking; body text
does not.

## Radius

| Surface | Radius | Style |
| --- | --- | --- |
| HUD bottom corners | `20 * scale` | `.continuous` |
| Settings modal | `16` | `.continuous` |
| Settings card | `16` | `.continuous` |
| Buttons, tags, indicator bars | Capsule | |

Always `.continuous`, never `.circular`. The island's radius is the one radius
that scales, because the whole shape scales as a unit.

## Spacing

The island uses `24` horizontal padding in the text band, widening to `46`
when a language tag is present so centered text stays centered. Vertical
padding is `9`. All scale.

Settings uses a `16` horizontal inset inside cards, `14` above a group title,
`8` below the last row, and `13` vertical per row. Rows are separated by a
1px rule rather than a gap. Standard control width is `150`, and the Settings
window is a fixed `860 × 600`.

## Elevation

Two shadows exist in the entire app.

The island casts `black` at `0.35` opacity, radius `11 * scale`, offset
`y: 4 * scale`. Its host window reserves `44` points of slack on the left,
right and bottom purely so that shadow is not clipped — nothing at the top,
because the shape is flush against the screen edge.

The Settings modal carries a soft shadow and a 1px low-opacity border. There
is no scrim behind it: the modal establishes focus with its own contrast, and
the desktop is not visible through it.

## Accessibility

Reduce Motion and Increase Contrast are both honored, and both are read from
the system rather than duplicated as app settings. Reduce Motion replaces
every animated voice visual with a quiet level meter and removes the
expand/collapse animation entirely. Increase Contrast raises the white
opacities listed above.

The one hard visual requirement in the whole product: silence and a dead
microphone must never look the same. Silence settles a visual to rest; a dead
microphone freezes it in amber.
