# Drop Transcription

The brief. Read `README.md` first for the aesthetic, `hud-anatomy.md` for the
shape this lives inside, and `motion.md` before proposing anything that moves.

## What it is

Most speech-to-text apps let you hand them a file and get text back. It is
always a file picker, a window, and a list. Talkify has a notch island, so it
can do something no one else can: you pick up an audio or video file, drag it
toward the top of the screen, the island opens to receive it, you drop it in,
and when it is done the island comes back holding the transcript as a file you
drag straight out to wherever you want it.

The file goes in through the notch and comes back out of the notch. That
symmetry is the whole feature. Everything below protects it.

## The gesture, start to finish

1. The user starts dragging a media file — from Finder, or anywhere that
   drags files.
2. Nothing happens yet. Talkify knows a drag is in progress, but reacting to
   every drag on the system is intrusive, so it waits.
3. The pointer crosses into a catch strip along the top edge of the display.
   The island peeks: it drops a few points below the notch. This says "I am
   here, keep coming."
4. The pointer continues toward the notch. The island opens fully into a drop
   target.
5. The user drops. The island confirms briefly, then dismisses.
6. Transcription runs in the background. The menu bar ghost carries progress.
   The user keeps working, and can still press Fn to dictate normally.
7. The transcript is written to disk.
8. The island returns holding a card. The user drags it wherever they want,
   or ignores it and it leaves after five seconds.

Only audio and video files trigger any of this. Drag a PDF at the top of the
screen and the island never appears.

## The three states to design

### 1. Armed

Two sub-states. **Peek** is a hint — the shape descends a few points below
the notch, nothing inside it. **Open** is the real target.

Open shows a media type glyph, the file name, and nothing else. The edge
carries a slow animated stroke in the accent blue, so it reads as live and
receptive.

Deliberately *not* the Edge Glow beam. That beam means "a microphone is
listening" and this is not that. It needs its own language, drawn from the
same vocabulary.

If the user has configured a second dictation language, the open target
splits into two labeled halves. Dropping on the left transcribes in one
language, the right in the other. The drop *is* the language choice. This
matters more here than for live dictation: Talkify never guesses a spoken
language, and picking wrong on a 40-minute file wastes minutes of compute and
returns confident nonsense.

Also needs: a rejecting state, for a file the feature cannot take.

### 2. Working

Barely exists on screen, which is the point. The drop lands, the island reads
"Transcribing memo.m4a" for roughly a second and a half, then collapses.

Progress moves to the menu bar. The proposal is that the ghost icon fills
with tint from the bottom as the job advances, like a battery. It reads at 16
points, needs no extra chrome, and it is the app's own mark doing the work.
The alternative is a ring drawn around the ghost.

The island must not sit on screen holding a progress bar. It is built for
sessions measured in seconds, and a long file takes minutes.

### 3. Finished

The one users will judge the feature by.

The island returns holding a card: a document glyph on the left, the file
name on the first line, and `1,240 words · 12:03` on the second, dimmed and
monospaced. Not the transcript text — a 40-minute transcript has no business
being rendered in an island.

Hovering swaps the cursor to an open hand. That is the entire grab
affordance and it costs nothing.

A hairline drains along the bottom edge for the five seconds it is visible.
The moment the pointer touches the card, the hairline freezes and fades and
the timer cancels. Ignore the card and it is gone in five seconds; reach for
it and it waits. Menus already behave this way, so nobody has to learn it.

Dragging lifts the card out and collapses the island behind it, so the file
visibly leaves through the same opening it went in. The drag image should be
the rendered card, not a generic file icon.

## Decisions already made

Do not redesign around these. They were argued out.

**The transcript is written to disk before the island returns.** The card is
a convenience over a durable result, never the only chance to catch it. This
is why five seconds is acceptable: dismissing it discards nothing.

**Default save location is beside the source file**, with a Settings option
for one fixed folder instead. If the source's location cannot be written — a
read-only volume, a mounted image, a network share — it falls back to the
chosen folder, then the Desktop.

**Because a real file already exists, the drag is an ordinary file drag.**
Dropping into a Finder folder on the same volume moves it; every other
destination copies it. That is behavior people already understand.

**Version 1 writes plain text** for audio and video alike. Timed subtitle
output is a later format.

**Transcription runs in the background** and does not block live dictation.

**Reveal only for audio and video**, decided by asking the system what the
file is, not by matching extensions.

**A menu bar item opens a file picker** for anyone who never discovers the
drag, and for anyone who cannot perform one.

## Constraints a design has to respect

The island's host window is fixed size and only its origin moves. The shape
can change size within it; the window cannot.

Bounce only in scale anchored at the top edge. Never in position — an
overshoot opens a visible gap against the screen edge.

Nothing is drawn in the housing band at the top of the shape. That space sits
behind the camera.

The shape is pure black and the fillets exist only on a real notched display.

The island still never takes keyboard focus, even now that it accepts the
mouse in these two states.

Reduce Motion needs an answer for every piece of motion proposed. A fade is
an acceptable answer.

Everything scales with the user's HUD size setting, 0.6 to 1.0, except the
housing band and fillets.

## Open questions for the design

Should the armed state show the file name, or stay anonymous until the drop?
Anonymous is cleaner, but it gives no confirmation the right file was
grabbed.

Ghost progress: fill or ring?

How does the split-language target read without looking like two buttons
bolted onto an island?

What does a rejecting state look like — a video with no audio track, or a
file that fails partway?
