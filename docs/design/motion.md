# Motion

Source: `Talkify/Dictation/HUD/DictationHUDShellView.swift`,
`Talkify/CoreHUD/HUDRevealStyle.swift`,
`Talkify/Dictation/HUD/Visuals/HUDCompactIndicatorView.swift`.

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

These four are the dictation picks, and the only reveal styles that exist.

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

## Drop Transcription

The drop surfaces ignore the reveal styles above entirely. They grow out of the
housing instead (`HUDSurface.growsFromHousing`): closed, the black really is
the size of the housing at an 8pt radius; open, it is the full shape at the
usual radius, and one spring carries it between the two. The content exists
only while open and arrives on `.scale + .opacity + .offset(y: -height/2)`.

That is NotchDrop's approach and its spring. It is not offered to dictation —
the notch opening is the Drop Transcription gesture, and dictation's shape is a
status surface rather than a target.

| What | Animation |
| --- | --- |
| Every size the shape takes | `.interactiveSpring(0.5, extraBounce: 0.25, blendDuration: 0.125)` |
| Hint ↔ target content | crossfade, carried by the same spring |
| The held file arriving | `.opacity` + `.scale` |
| Everything else — card, notice, retract | no animation of its own |

`extraBounce` is the whole point: the shape passes its new size and settles
back into it, which is what makes the notch read as snapping open rather than
resizing. Applying that spring only to the reveal, as this first did, hides the
effect exactly where it is most visible — the peek growing into the target.

Two traps, both of which produced real defects:

**The size animation belongs on the surface, not in its content.** `HUDSurface`
applies the size as a frame *around* the content handed to it, so an animation
attached inside that content never reaches the frame — the shape jumps while
the words inside it animate.

**A reveal needs one drawn frame in the parked state.** `HUDRootView` swaps
between the dictation shell and the drop shape on `mode`, so the shell is
always mounted and its reveal animates against a frame that already exists;
the drop shape is inserted into the tree at the same moment it is asked to
open, and a view that has never rendered has nothing to animate from. Forcing
layout does not fix it and there is no callback for "SwiftUI has drawn", so
`HUDStage.revealDrop()` waits one display cycle before flipping. Without it the
transcript card opened with no animation at all while the target sprang
correctly.

Four attempts at animating the moment between the drop and the card were
rejected; `FEATURE.md` lists them. Read that before proposing motion here.

Reduce Motion: no spring, no transitions — the sizes change instantly.

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
