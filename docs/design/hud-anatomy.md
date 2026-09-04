# HUD anatomy

Source: `Talkify/CoreHUD/HUDMetrics.swift`, `Talkify/CoreHUD/HUDNotchGeometry.swift`,
`Talkify/Dictation/HUD/DictationHUDShellView.swift`.

The HUD is a black shape that descends from the top center of a display and
appears to grow out of the MacBook's notch. It is the app's primary surface.
Every dictation status and error message appears here and nowhere else.

## The shape

Square against the top of the screen, rounded at the bottom two corners,
flared into the bezel on a real notched display. Filled pure black. It reads
as the notch itself stretching downward.

```
        screen top edge
 ───────┬─────────────────┬───────
        │▓▓▓ housing  ▓▓▓ │          ← camera lives here; flanks can carry Waveform + Draft
 ╭──────┴─────────────────┴──────╮
 │                               │   ← visual band (voice visual)
 │                               │
 │        draft text band        │   ← text band, only for some visuals
 ╰───────────────────────────────╯
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
| Waveform + Draft hanging stage | `40 * scale` | yes |
| Waveform + Draft ribbon | `12 * scale`, inside the hanging stage | yes |
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

**Housing band.** Always present. Its height is the notch's height. The
camera sits in the middle of this strip, so Compact, Waveform, Edge Glow,
and status messages leave it empty. Waveform + Draft is the exception: its
recent-word line is an overlay centered on the housing-plus-stage
silhouette, because the flanks of that strip are still visible beside the
camera. The camera itself stays empty.

**Visual band.** Holds the voice visual. Its height depends on which visual
is selected: `64 * scale` for Waveform, `64 * scale` (empty, used as a stage
for edge-hugging light) for Edge Glow, `24 * scale` for the Reduce Motion
level meter, and zero for Compact and Waveform + Draft, whose indicator and
Chart Line ribbon live inside the text band instead.

**Text band.** Holds live draft text. Present for Compact and Waveform +
Draft, absent for Waveform and Edge Glow while listening, and always present
under Reduce Motion. Draft text is 15pt medium white and centered, except
Compact (leading, beside the five-bar indicator) and Waveform + Draft (a
`24 * scale` recent-word line centered in the island, overlaying housing
plus a `40 * scale` hanging stage). Compact keeps the three long-draft
behaviors the user picks between: single line with head truncation, wrap
and grow downward capped at four lines, or single line that shrinks to
fit. Waveform + Draft does not: eight tokens on one line, and a line that
does not fit clips the oldest words instead of ellipsizing each one.

**Language tag.** A small capsule shown only when a second dictation
language is configured. It hangs off the shell as an overlay rather than
sitting in the layout, so it never changes the window's size. Compact,
Waveform, Edge Glow, and status messages pin it to the top leading corner
below the housing. Waveform + Draft overlays it on the leading edge of the
island, vertically centered with the draft.

## Hard rules that keep being violated

These are load-bearing. Breaking one produces a visible defect on real
hardware, not a style disagreement.

**The host window never resizes.** It is sized once for the tallest possible
layout at 100% scale, and only its origin moves. A smaller shape centers
itself inside the same fixed window.

**Bounce lives only in top-anchored scale, never in position.** A position
overshoot lifts the shape off the screen edge and opens a visible gap above
it. Scale anchored at `.top` cannot.

**Nothing is drawn in the housing band**, except Waveform + Draft's
recent-word overlay, which is centered on the housing-plus-stage
silhouette so the line sits in the visible flanks rather than only under
the camera. Status messages, Compact, Waveform, and Edge Glow still leave
the housing empty.

**Fillets require a real notch.** Zero otherwise.

**The HUD descends from the top center and is never placed at the bottom.**

**Window level is `.mainMenu + 3`** so it clears full-screen apps, and it
appears on every Space. No private APIs anywhere.

## Interaction

Historically none: the HUD ignored all mouse events and never took focus, so
clicks passed straight through to whatever was behind it
(`HUDPanel.swift`).

This is changing for Drop Transcription. The HUD now accepts the mouse in
exactly two states — while it is a drop target, and while it holds a finished
transcript — and still never takes focus. In every other state it remains
click-through. See `FEATURE.md`.

## Display behavior

The HUD opens on the display containing the focused input. If that is
unknown, the display containing the pointer. If that fails, the main display.
Its display is locked when a session starts and does not follow windows. If
that display disconnects mid-session, the HUD moves to the pointer's display.

Every display behaves identically. Only the notch measurement differs.
