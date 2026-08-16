# Settings UI

Source: `Talkify/Settings/`.

Not part of Drop Transcription's main surface, but it defines the app's
component vocabulary, and the feature adds one setting to it.

## The window

A borderless AppKit window hosting SwiftUI. Fixed `860 × 600`, 16pt
continuous radius, 1px low-opacity border, soft shadow. Dark only — the
system can still override contrast and motion, but there is no light mode.

It is a centered modal surface, not a standard titled window. It closes with
a leading `xmark` control or Escape. Clicking outside does not dismiss it. It
does not resize; content scrolls internally. It uses normal window level, so
it activates when opened but does not float above other apps. Dragging the
header moves it; controls and content are not draggable.

Layout is a fixed sidebar plus a scrolling content pane. The header shows the
close control on the leading edge, matching native window controls, and
centers the Talkify identity: the ghost icon and the app name.

## Components

**Card** (`SettingsCard`) — a labeled group of related rows. 16pt continuous
radius, card fill, 1px border at white `0.09`. Group title is 11pt semibold,
tracking `0.6`, white `0.44`, with 16pt horizontal inset, 14pt above and 4pt
below.

**Row** (`SettingsRow`) — title, optional description, trailing control.
13pt medium title, caption description at white `0.48`. 13pt vertical
padding, separated by a 1px rule at white `0.07` rather than a gap.

**Picker row** — a row whose control is a trailing `.menu` picker, 150pt
wide. Used for anything with named choices.

**Slider row** — a row whose control is a slider plus a monospaced-digit
readout in a fixed 36pt trailing column. The slider is visually continuous
and snaps its stored value to a step in the binding, because a stepped
SwiftUI slider draws tick marks and they read as clutter on this surface.

**Button** (`SettingsButtonStyle`) — capsule, 12pt semibold, white `0.10`
fill rising to `0.18` pressed, white `0.12` border, 0.97 scale while pressed,
0.45 opacity when disabled.

**Key recorder** — arms on click and captures the next key pressed, System
Settings style.

## Rules

A preference gets a slider only when it has no natural set of named choices,
and a slider always steps so any stored value can be picked again.

Changes apply live and persist immediately. There is no Save step and no
reset control.

Related rows share one card with separators. Do not float multiple small
cards.

Sections appear only once their behavior exists. No placeholder or disabled
sections, ever.

The Appearance section shows a live HUD preview at the top, rendered with the
same surface and preferences as a real session, on fixed notched-MacBook
reference geometry.

## What Drop Transcription adds

One row: where a transcript is written. Two choices, so it is a picker rather
than a slider — next to the source file (default), or a folder the user picks.
Choosing the second reveals a folder chooser.

It belongs in a card of its own inside a Drop Transcription section, or in
the existing structure if the section turns out to hold only this one row.
