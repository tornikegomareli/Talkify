# HUD anatomy

Source: `Talkify/CoreHUD/HUDMetrics.swift`, `Talkify/CoreHUD/HUDNotchGeometry.swift`,
`Talkify/Dictation/HUD/DictationHUDShellView.swift`.

The HUD is a black shape that floats near the bottom center of a display,
its housing cap meeting the display's bottom edge. It is the app's primary
surface. Every dictation status and error message appears here and nowhere
else.

## The shape

Square against the bottom of the screen, rounded at its bottom two corners,
flared into the bezel along the bottom edge on a real notched display. Filled
pure black. It reads as the display's housing cap.

```
 ╭───────────────────────────────╮
 │        draft text band        │   ← text band, only for some visuals
 │                               │
 │                               │   ← visual band (voice visual)
 ╰──────┬─────────────────┬──────╯
        │▓▓▓ housing  ▓▓▓ │          ← housing cap, always empty
 ───────┴─────────────────┴───────
        screen bottom edge
```

The fillets are the small concave corners where the shape meets the bezel.
They exist only on a display that reports a real notch. On any other display
they are omitted, because without a physical housing to hug they read as two
detached tabs.

## Measurements

| Part | Value | Scales? |
| --- | --- | --- |
| Shape width | `540 * scale` | yes |
| Text band height | `36 * scale` min, `120 * scale` max | yes |
| Visual band, Reduce Motion | `24 * scale` | yes |
| Visual band, waveform / glow | `64 * scale` | yes |
| Bottom corner radius | `20 * scale` | yes |
| Housing, measured notch | whatever the display reports | **no** |
| Housing, simulated | `185 × 32` | **no** |
| Fillet | `11`, or `0` with no notch | **no** |
| Shadow slack in host window | `44` | no |

`scale` is the user's HUD size setting: 0.6 to 1.0, 0.05 steps, default 1.0.

The split matters. The shape scales as one piece so a smaller HUD keeps its
voice visual instead of trading it away. The housing band and fillets never
scale, because the housing height is literally hardware on a notched Mac and
menu-bar clearance everywhere else, and a fillet exists to meet a physical
bezel curve.

## The bands

**Housing band.** Always present, always empty. Its height is the notch's
height, or the fixed stand-in cap elsewhere. Nothing is ever drawn here —
the cap stays empty so the shape reads as the housing.

**Visual band.** Holds the voice visual. Its height depends on which visual
is selected: `64 * scale` for Waveform, `64 * scale` (empty, used as a stage
for edge-hugging light) for Edge Glow, `24 * scale` for the Reduce Motion
level meter, and zero for Compact, whose indicator lives inside the text band
instead.

**Text band.** Holds live draft text. Present for Compact, absent for
Waveform and Edge Glow while listening, and always present under Reduce
Motion. Draft text is 15pt medium white, centered, with three long-draft
behaviors the user picks between: single line with head truncation, wrap and
grow downward capped at four lines, or single line that shrinks to fit.

**Language tag.** A small capsule pinned to the top leading corner of the
shape, shown only when a second dictation language is configured. It hangs
off the shell as an overlay rather than sitting in the layout, so it never
changes the window's size.

## Hard rules that keep being violated

These are load-bearing. Breaking one produces a visible defect on real
hardware, not a style disagreement.

**The host window never resizes.** It is sized once for the tallest possible
layout at 100% scale, and only its origin moves. A smaller shape centers
itself inside the same fixed window.

**Bounce lives only in bottom-anchored scale, never in position.** A position
overshoot lifts the shape off the screen edge and opens a visible gap. Scale
anchored at `.bottom` cannot.

**Nothing is drawn in the housing band.**

**Fillets require a real notch.** Zero otherwise.

**The HUD anchors to the bottom center and is never placed at the top.**

**Window level is `.mainMenu + 3`** so it clears full-screen apps, and it
appears on every Space. No private APIs anywhere.

## Interaction

Historically none: the HUD ignored all mouse events and never took focus, so
clicks passed straight through to whatever was behind it
(`HUDPanel.swift`).

The HUD accepts the mouse in three states — while it is a drop target,
while it holds a finished transcript, and while an editable draft is under
review — and still never activates Talkify. Only the draft review takes
keyboard focus, inside the non-activating panel. In every other state it
remains click-through. See `FEATURE.md`.

## Display behavior

The HUD opens on the display containing the focused input. If that is
unknown, the display containing the pointer. If that fails, the main display.
Its display is locked when a session starts and does not follow windows. If
that display disconnects mid-session, the HUD moves to the pointer's display.

Every display behaves identically. Only the notch measurement differs.
