# Motion

Source: `Talkify/HUD/Shell/DictationHUDShellView.swift`,
`Talkify/HUD/Shell/HUDRevealStyle.swift`,
`Talkify/HUD/Visuals/HUDCompactIndicatorView.swift`.

Every animation in the app, with its real values. If a new surface needs
motion, take a spring from this list rather than inventing one.

## The rule behind the rule

The shape's top edge is glued to the top of the screen. Any animation that
moves the shape's position and overshoots will lift it off that edge and open
a gap between the shape and the screen. That gap is instantly visible on a
notched Mac, because the illusion is that the shape *is* the notch.

So: **bounce is expressed in scale anchored at the top, never in position.**
The two styles that move position are bounce-free by construction. This is
not a preference and it applies to anything new.

## Reveal styles

Four, user-selectable, default Slide. Each defines a parked state and an
animation.

| Style | Parked at | Enters with | Leaves with |
| --- | --- | --- | --- |
| Slide | `y: -(height + 20)` | `.spring(0.4, bounce: 0)` | `.spring(0.28, bounce: 0)` |
| Unfurl | `scaleY: 0.001` | `.spring(0.45, bounce: 0.3)` | `.spring(0.28, bounce: 0)` |
| Bloom | `scale: 0.55`, opacity 0 | `.spring(0.4, bounce: 0.25)` | `.spring(0.28, bounce: 0)` |
| Drift | `y: -14`, opacity 0 | `.easeOut(0.24)` | `.easeIn(0.18)` |

Slide arrives from outside the screen edge. Unfurl unrolls downward out of
the housing and settles back — the bounciest of the set. Bloom inflates from
the housing while fading in. Drift barely moves and is the most understated.

Scale is always anchored `.top`.

## Other animations

| What | Animation |
| --- | --- |
| Visual band height change | `.spring(0.25, bounce: 0)` |
| Draft text growing downward | `.spring(0.25, bounce: 0)` |
| Compact indicator settling to rest | `.easeOut(0.25)` |
| Reduce Motion, all reveals | `.easeOut(0.12)` fade |

## Audio-reactive timing

The microphone level is smoothed with a decay rather than tracked raw:

```
level = max(newLevel, previousLevel * 0.88)
```

Attack is instant, release is gradual. Anything that reacts to voice should
feel like this — jumping up immediately and falling off softly. A raw level
looks like noise.

The Compact indicator's five bars each ride the level with their own phase
offset (`sin(time * 9 + index * 1.7)`), so the cluster shimmers like sound
instead of pumping as a single block. Bars rest at 3pt and reach roughly 14pt
at full level.

## Duration conventions

Status and error messages dismiss themselves after about two seconds. That
number applies to messages the user only has to read.

It does **not** apply to anything the user has to act on. A surface that asks
for an action and then vanishes is a WCAG 2.2.1 timing failure. Drop
Transcription's finished card uses five seconds and pauses that timer on
hover for exactly this reason — see `FEATURE.md`.

## Reduce Motion

When the system setting is on, every animated voice visual is replaced by a
quiet level meter, the expand and collapse animation is skipped entirely, and
all four reveal styles collapse to a 0.12s fade. Reduce Motion also forces
the draft text band to always show, regardless of which visual is selected.

Any new motion needs a Reduce Motion answer. "Fades instead" is an acceptable
answer. "Animates anyway" is not.
