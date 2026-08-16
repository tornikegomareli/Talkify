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
7. The transcript is staged in a temporary folder under its final name.
8. The island returns holding a card. Dragging it out is the save — the file
   lands wherever it is dropped. Ignore it and after five seconds the island
   writes the transcript to the Save-to location, says which folder, and
   leaves.

Only audio and video files trigger any of this. Drag a PDF at the top of the
screen and the island never appears.

## The three states to design

### 1. Armed

Two sub-states. **Peek** is a hint — the shape descends a few points below
the notch, nothing inside it. **Open** is the real target.

Open shows a media type glyph, the file name, and nothing else. The edge
carries a dashed accent stroke, so it reads as live and receptive.

The accent is not fixed. It follows the voice visual: with Edge Glow selected
the target wears that palette — the full gradient on its edge, where there is
length enough to show a palette off, and the palette's one representative hue
on the glyph, the peek bar and the closing line. Sunset makes an orange target;
Aurora a green one. Every other visual keeps the Talkify blue. It is the same
hue the status ghost takes during a glow session, so a palette means one colour
across the whole app — except Settings chrome, which stays blue on purpose. The peek bar breathes for the same reason: a pointer crossing the
top of the screen catches movement, never a static tab.

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

**The drop has an ending you can watch.** Releasing the file does not start
anything: the shape takes it and holds it — the file's own icon, its name —
for about a second, so the gesture finishes with the thing you dragged visibly
inside the notch. Only then does the shape close and the job begin. This is
NotchDrop's tray, narrowed to one item: what you gave it is shown back to you
before it is acted on.

After that, nothing on screen. The island collapses and the menu bar ghost
carries the job from there.

**Never dismiss the target on mouse-up.** Talkify watches the drag through a
global event monitor, and that monitor sees the button come up. Acting on it —
hiding the HUD, which stops the panel accepting the mouse — pulls the
destination out from under the drop AppKit is at that moment delivering to it.
macOS answers a refused drop by flying the item back to where it came from, and
that flight is the "slow", "sluggish", "scattered" drop. It is not the
handler's speed and no amount of work removed from the handler fixes it.

So a release over the open target is left entirely to the drop. Only a release
elsewhere in the catch area dismisses the target directly. A watchdog closes
the target if the drop never arrives.

**The drop handler does nothing and says yes.** The system holds the dragged
item on the pointer until the destination answers, so every instruction that
runs before the answer is time the item spends stuck to the cursor.

So the handler reads nothing. Not the item, not the file, not the pasteboard.
It returns true and schedules the real work for the next turn of the run loop.
Two things make that safe:

- `dropDestination(for: URL.self)` cannot be used, because it answers only
  after decoding the item's `Transferable`. `onDrop(of:isTargeted:perform:)`
  hands over the providers untouched and takes a synchronous Bool.
- Talkify already knows the file. `DragWatcher` read it from the drag
  pasteboard on the way in — that read is what opened this target, and the drag
  pasteboard cannot change mid-drag — so the drop needs to carry nothing but
  which half of a split target it landed on.

A drop the target never armed for is ignored rather than guessed at.

Four attempts at filling this moment have been rejected, and the list is here
so a fifth does not repeat them:

1. Announcing the start in words ("Transcribing memo.m4a") — two unrelated
   surfaces in the same spot seconds apart, and the swap between them was the
   ugliest moment in the feature.
2. A half-second confirm, the shape drawing in around the media glyph under a
   band of light — too short and too vague to read as anything.
3. Three Metal materials worn by the shape for the length of the job — a
   refractive glass lens, concentric distortion waves, and glowing harmonic
   strings. All three rejected on sight.
4. One pass of the Edge Glow beam across the shape as the file is absorbed —
   the app's own beam, its own palette, its own mask shader. Also rejected.

The common thread: none of them said how much longer, because the island
cannot. A long file takes minutes, and a surface that says "working" without
saying how much longer is decoration.

Progress moves to the menu bar. The ghost icon fills from the bottom as the
job advances, like a battery: it reads at 16 points, needs no extra chrome, and
it is the app's own mark doing the work.

It fills in the drop accent, not in the menu bar's white — the same colour the
target and the card are wearing, so a Sunset palette makes an orange ghost. The
whole silhouette is that colour and only its weight changes at the progress
line. This means the icon cannot be a template image, since the menu bar would
recolour a template straight back to white.

The island must not sit on screen holding a progress bar. It is built for
sessions measured in seconds, and a long file takes minutes.

### 3. Finished

The one users will judge the feature by.

The island returns holding a card: a document glyph on the left, the file
name on the first line, and `1,240 words · 12:03` on the second, dimmed and
monospaced. Not the transcript text — a 40-minute transcript has no business
being rendered in an island.

Hovering swaps the cursor to an open hand, and the second line trades the
numbers for `Click to copy · Drag to save`. The card has two gestures and
neither is visible; the hint appears only while the pointer is there, which is
the only moment it can be acted on.

The drag carries the transcript twice — the written file and the same text as
plain text — and the receiver picks which it wants. A folder writes the `.txt`;
a text field takes the words. That is the platform's own answer to this
question, and the reason dragging selected text out of TextEdit inserts words
into a text field but leaves a file in Finder.

Length is deliberately not part of that decision. Every product that switches
format by length is a chat client applying its own message limit — Discord at
2,000 characters, Slack against its own — and only a receiver knows what will
not fit. Talkify cannot, so it offers both and lets each destination answer.
Clicking is the escape hatch for receivers that always prefer a file: it puts
the transcript on the clipboard, says `Copied`, and ends the job.

A hairline drains along the bottom edge for the five seconds it is visible.
The moment the pointer touches the card, the hairline freezes and fades and
the timer cancels, and it stays cancelled for as long as a drag from the card
is in flight. Ignore the card and it is gone in five seconds; reach for it and
it waits. Menus already behave this way, so nobody has to learn it.

The card expiring is not a dismissal. It commits: the transcript goes to the
Save-to location and the shape holds one line naming the folder for about a
second and a half before retracting. That line exists because the write now
happens after the card is gone, and a save nobody sees is a save nobody
trusts.

Dragging lifts the card out and collapses the island behind it, so the file
visibly leaves through the same opening it went in. The drag image should be
the rendered card, not a generic file icon.

## Decisions already made

Do not redesign around these. They were argued out.

**The transcript is staged, not saved, while the card offers it.** It is a
real file in a temporary folder from the moment transcription ends, so the
drag always has something to carry and a quit never loses it. Where it ends
up is the user's choice, and the card is where they make it.

**Dragging the card out is the save.** A destination that accepts the file
ends the job and nothing is written anywhere else. Dragging it into Mail or
onto another volume copies it, which is still the user having chosen; the
staging folder is removed either way.

**The card expiring saves it for you.** Five seconds untouched and the
transcript goes to the Save-to location. This is the fallback, not the
default path — the notch is.

**Default save location is beside the source file**, with a Settings option
for one fixed folder instead. If the source's location cannot be written — a
read-only volume, a mounted image, a network share — it falls back to the
chosen folder, then the Desktop.

**The drag is an ordinary file drag, copy-only.** The staged file lives
somewhere the user never sees, so moving it out of there would mean nothing
to them. Every destination gets a copy and Talkify cleans up after itself.

**The drag offers text as well as the file, and the receiver chooses.** There
is no length threshold anywhere in Talkify; a click is the deterministic way
to ask for text.

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
