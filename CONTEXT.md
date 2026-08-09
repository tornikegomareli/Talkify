# Talkify

Talkify is a native macOS speech utility focused on immediate spoken interaction with applications and live audio.

Talkify targets macOS 26 on Apple Silicon. It does not ship an Intel executable.
Talkify is a menu-bar-only app with no persistent Dock icon.
Talkify offers a disabled-by-default “Launch at Login” setting through `SMAppService`.

The first implementation milestone contains only **Direct Dictation**. Other features remain deferred until its latency benchmark passes.

## Architecture

- Talkify builds from a committed Xcode project (`Talkify.xcodeproj`) without Tuist or any project generation
- AppKit is the application shell: lifecycle, menu bar status item, and non-activating panels such as the HUD
- SwiftUI renders windowed UI such as settings and onboarding, hosted inside the AppKit shell
- Talkify uses Swift 6 with complete strict concurrency
- Talkify uses Apple frameworks only and has no third-party dependencies

## Language

**Direct Dictation**:
A session that converts the user's microphone speech into text for the previously focused control.
_Avoid_: Voice typing, transcription mode

**Dictation Trigger**:
The configured keyboard input that controls **Direct Dictation** through press, release, and tap gestures.
_Avoid_: Hotkey, shortcut

**Live Captions**:
Ephemeral text produced from a selected application's live audio and displayed while that audio continues.
_Avoid_: Subtitles, meeting transcription

**Caption Source**:
The single running application whose audio produces **Live Captions**.
_Avoid_: Meeting app, audio source

**Meeting Transcript**:
Saved, timestamped text produced from meeting audio.
_Avoid_: Live Captions, meeting notes

**Subtitles**:
Timed text exported for recorded media in a format such as SRT or VTT.
_Avoid_: Live Captions

**Speech Model**:
An Apple-managed, on-device language asset used by the Speech framework.
_Avoid_: Bundled model, Talkify model, Whisper model

**Settings section**:
A navigable category of persisted application preferences with a visible user-facing purpose.
_Avoid_: Placeholder tab, settings page

**Settings group**:
A labeled collection of related Settings sections in the navigation rail.
_Avoid_: Disabled section, feature preview

**Appearance preview**:
A compact live rendering of the Direct Dictation HUD used to show Appearance changes before dictation.
_Avoid_: Mock preview, static screenshot

**Dictation session settings**:
An immutable snapshot of all Appearance and Sounds preferences captured when Direct Dictation starts.
_Avoid_: Draft settings, temporary preferences

**Insights**:
A local Settings section that summarizes aggregate **Direct Dictation** activity.
_Avoid_: Transcript history, cloud analytics

## Relationships

- Pressing the **Dictation Trigger** starts **Direct Dictation** immediately
- The default **Dictation Trigger** is Fn and onboarding lets the user change it
- Releasing a held **Dictation Trigger** ends **Direct Dictation** and inserts its text
- Releasing the **Dictation Trigger** before 250 milliseconds counts as a quick tap
- A quick tap leaves **Direct Dictation** active until the next trigger press
- The **Direct Dictation** HUD shows live draft text while speech continues, unless the selected voice visual replaces it; with Reduce Motion the draft text always shows
- The HUD renders volatile recognition results immediately
- **Direct Dictation** inserts finalized recognition text plus the latest volatile result when recognition ends before finalizing it
- The **Direct Dictation** HUD expands from the physical notch on the focused input's display
- Settings exposes **Appearance**, **Sounds**, and **Insights** in that order
- The Settings navigation supports labeled groups, but renders no empty or disabled sections
- A new Settings section appears only after its underlying preferences and behavior exist
- If the focused input's display is unknown, the HUD uses the display containing the pointer
- If no display contains the pointer, the HUD uses the main display
- The HUD always descends from the top center of its display and is never placed at the bottom
- Displays without a physical notch show a simulated notch: the same surface with a stand-in footprint
- The simulated notch omits the corner fillets that hug a physical housing
- The HUD behaves identically on every display; only the notch measurement differs
- The HUD appears above full-screen applications and on every Space
- The HUD is display-only: mouse clicks pass through it and it never takes focus
- The HUD's display is locked when the session starts and does not follow windows
- If the HUD's display disconnects mid-session, the HUD moves to the pointer's display
- The HUD is the only surface for dictation status and error messages
- HUD status and error messages dismiss themselves after about two seconds
- The HUD shows a live visual that reacts to microphone audio while listening
- Settings changes apply to the live app and persist immediately; Settings has no Save step
- The Appearance preview uses the same preferences and HUD surface as Direct Dictation
- Settings changes update the Appearance preview immediately, while an active Direct Dictation session keeps the choices captured at session start
- Dictation session settings include the voice visual, waveform style, glow palette, glow center, reveal style, long-draft behavior, and sound set
- A third voice visual, Compact, shows a small five-bar voice indicator beside the leading-aligned live draft inside the shape, after the iOS Dynamic Island caption look; the shape grows with the draft
- Compact is the only visual that shows the live draft while listening; Waveform and Edge Glow replace the draft text entirely
- An In the Shape live-draft placement for Waveform and Edge Glow was prototyped and removed; the draft-in-shape presentation belongs to Compact alone
- A detached child pill under the island (the uni-pills goo bubble) was prototyped as a third placement and rejected by feel: a second detached surface does not fit the single-shape design
- Reduce Motion overrides every live draft placement with the plain text band and quiet level meter
- `AppSettings` is the only persisted source of truth for preferences; the Dictation controller creates Dictation session settings for the HUD at session start
- Future Settings sections are registered in code with stable typed IDs, group metadata, backing behavior, and tests; remote or plugin-defined sections are out of scope
- Appearance shows the live preview first, then the Voice visual and Motion and layout groups
- The Talkify Settings window is dark-only; system accessibility settings still override contrast and motion treatment
- Settings follows Reduce Motion and Increase Contrast without adding duplicate app-level toggles; VoiceOver labels are deferred
- Future user-controlled visual options belong to a separate Customization section, not the system accessibility boundary
- Customization is a provisional section name and may change before that section ships; it is not shown in the first Settings menu
- Future Customization options reuse the Appearance preview and Dictation session settings snapshot; no speculative options are shown now
- Customization remains an extension point until a concrete control has defined behavior, preview, persistence, and session effects
- The Appearance preview stays in a labeled simulated listening state; it has no idle/listening mode switch
- Two preview picks are invisible in the idle listening state, so changing them plays a one-shot demo: Reveal style replays the reveal, and Long draft behavior shows a wrapped long draft before listening resumes
- Development Settings exposes every implemented sound set, including Pop; the production picker excludes non-shippable sets before publishing
- Incomplete sound sets are hidden from Settings; an unavailable selected set disables preview and cannot be persisted
- The first Appearance and Sounds release has no reset control; reset becomes a confirmed section-level action after more settings exist
- **Insights** appears directly below **Sounds** in Settings and has no separate menu-bar entry or window
- Settings appears as a centered modal surface with custom dark glass content instead of a standard titled window
- Settings closes through its explicit close control or Escape; clicking outside the modal does not dismiss it
- Settings uses a fixed-size surface with internal scrolling rather than user resizing
- Settings opens centered on the pointer's display on first launch, falls back to the main display, and preserves its frame afterward
- Settings uses normal window level; it activates when opened but does not stay above other applications
- The fixed Settings surface can be moved by dragging its header; controls and content remain non-draggable
- Settings closes with a top-left `xmark` control or Escape; VoiceOver labels are deferred for this milestone
- Settings controls use native SwiftUI Pickers, Toggles, and Buttons with Talkify's dark styling
- Voice visual uses a trailing menu picker so the control scales when more visual styles are added
- Related Settings rows share rounded cards with subtle separators instead of separate floating cards
- The modal uses a near-black surface with restrained material highlights and borders; desktop content is not visible through it
- Settings does not add a full-screen dimming window; the modal surface establishes focus with its own contrast and shadow
- Settings remains open when Talkify loses focus and returns when the user selects it again
- Talkify owns one Settings surface; reopening activates the existing window instead of creating a duplicate
- Settings section changes use a short crossfade or no transition, and Reduce Motion removes the transition
- The Settings sidebar stays fixed while the selected section's content pane scrolls
- Appearance controls are conditional: Waveform settings belong to Waveform, and Glow settings belong to Edge Glow; hidden values remain persisted
- Sounds Preview plays the selected Begin and End pair; the Paste sound remains an internal insertion event
- Settings preserves its selected section and window frame while the app runs, and opens on Appearance after a fresh launch
- The voice-reactive visual must make silence and a dead microphone look different
- With Reduce Motion enabled, the HUD replaces the animated visual with a quiet level meter and skips expand/collapse animation
- Version 1 inserts raw finalized text without filler-word or AI cleanup
- Text cleanup is a later feature and must not affect the first implementation
- Version 1 uses one user-selected recognition language and does not auto-detect languages
- Speech models use Apple's `lingering` retention policy
- Talkify prepares the selected speech model shortly after launch
- Talkify does not bundle or train speech models
- Onboarding installs the Apple-managed language asset only when it is missing and waits for completion
- Talkify uses Apple Speech exclusively and has no Whisper fallback
- Language selectors show only locales supported by Apple Speech
- Version 1 uses the current macOS default microphone
- Talkify follows system input-device changes between sessions; a device change during an active session may end that session
- Version 1 has no microphone device picker
- Onboarding requests microphone, Accessibility, and Input Monitoring permissions
- **Live Captions** requests system-audio permission only when first used
- **Direct Dictation** refuses to record for a focused secure password field and shows “Secure field”
- Pressing Escape cancels active **Direct Dictation** immediately without inserting text
- If **Direct Dictation** hears no speech in the first 15 seconds, it closes and inserts nothing
- Once speech has arrived, the session stays open until the user ends or cancels it
- **Direct Dictation** ends by inserting text into the previously focused control
- **Direct Dictation** tries Accessibility insertion before clipboard paste
- Talkify remembers the working insertion route for each application to avoid repeated failed attempts
- Clipboard paste restores the previous clipboard after the target application consumes the paste event
- If the original text target disappears, Talkify places finalized text on the clipboard without showing a message
- Early versions persist no audio, recognized text, captions, or transcript history
- Talkify persists application settings and aggregate **Direct Dictation** usage; macOS manages permission state
- **Insights** stores only the local calendar day, word count, speaking duration, and completed-session count
- **Insights** never stores recognized text or target application identifiers
- A completed **Direct Dictation** session with nonempty inserted text updates **Insights**
- **Insights** shows words, sessions, speaking time, weighted words per minute, Voice Momentum, 14-day activity, streaks, and a 16-week heatmap
- Settings lets the user choose the session sounds, the voice-reactive visual, the waveform style, and the edge glow's color palette
- Insertion latency must be benchmarked before choosing permanent per-application defaults
- Mid-session insertion was prototyped (streamed finalized chunks; a ghost overlay over the focused input) and rejected: insertion stays at session end, and no live-draft direction for Waveform and Edge Glow is chosen yet
- A marked-text input method (system-dictation-style provisional text in any field) remains a considered route, deferred: it needs a separate installable input-source bundle, System Settings enablement, and cross-process wiring
- **Live Captions** consume exactly one **Caption Source** and never microphone audio
- A **Live Captions** session starts only after the user confirms its **Caption Source**
- **Live Captions** display text without saving it
- **Live Captions** use a movable, non-activating, always-on-top panel
- The **Live Captions** panel starts at the bottom center of the screen
- The panel shows the current caption and one previous finalized line
- The panel discards older caption text
- **Live Captions** remain active during temporary source silence
- **Live Captions** stop and close when the **Caption Source** quits
- **Live Captions** use a language selection separate from **Direct Dictation**
- Turning on the **Live Captions** toggle confirms the source and language before capture starts
- Turning off the **Live Captions** toggle closes the active caption session
- Browser sources are labeled as capturing all browser audio because capture cannot isolate one tab
- Version 1 shows **Live Captions** without speaker names or speaker labels
- **Live Captions** show volatile text immediately and replace it as recognition improves
- **Live Captions** are provisional and may be removed from the product
- Further **Live Captions** design is paused until the feature is confirmed
- A **Meeting Transcript** persists finalized meeting text
- **Subtitles** belong to recorded media rather than a live meeting

## Example dialogue

> **Dev:** "Should turning on **Live Captions** create a **Meeting Transcript**?"
> **Domain expert:** "No. **Live Captions** are ephemeral; saving a **Meeting Transcript** is a separate action."

## Flagged ambiguities

- The HUD currently receives the live `AppSettings` object during a session; resolved: session-scoped Appearance and Sounds choices must be snapshotted at session start, while the Settings preview remains live. Implementation is pending.

- The edge glow's center content is a Settings pick under feel test: the particle cloud or the rotating Siri orb (artwork copied from GetStream's purposeful-ios-animations, which publishes no license and imitates Apple's Siri orb — see LICENSE-ARTWORK.txt). Unresolved: whether the orb stays; it cannot ship with this artwork.
- Development Settings exposes Siri Orb for feel testing; production Settings must exclude it until the artwork is replaced or licensed.
- Development Settings presents experimental options like normal choices; it does not add warning labels.
- Publish filtering uses centralized `isShippable` metadata rather than view-specific exclusions
- Defaults remain production-safe: Synth8, Waveform, Chart Line, and Particles; experimental choices are opt-in only
- Development builds preserve stored experimental choices; fallback migration is deferred until the publishing decision
- The first Settings group is labeled `SETTINGS`; future groups use the same compact uppercase navigation style
- The custom Settings surface is a borderless AppKit window hosting SwiftUI, not a sheet attached to the status menu
- Settings labels use the domain term Direct Dictation where scope matters and avoid Voice typing or Transcription
- DirectDictationController creates Dictation session settings at session start and passes them to DictationHUDController
- Direct Dictation uses the captured sound set for Begin, End, and Paste; Settings Preview reads the live AppSettings sound set only
- The session snapshot is captured after target and permission guards pass, immediately before the HUD begins listening
- The borderless Settings header shows the close control on the leading edge (matching native macOS window controls), then Talkify identity and a Settings title
- The sidebar retains the `SETTINGS` group label even when the header also shows Settings; it distinguishes navigation groups
- The Settings header uses the current waveform symbol until a dedicated Talkify icon exists; the icon slot stays stable for that replacement
- Replacing the temporary header symbol with the Talkify icon must not change the Settings layout
- The Settings surface uses a 16-point continuous radius, a one-pixel low-opacity border, and a soft shadow
- Settings may open during Direct Dictation; the active session remains on its captured settings and changes apply next session
- While Direct Dictation is active, Settings shows a small contextual notice that changes apply to the next session; idle Settings has no notice
- The active-session notice sits under the modal header on Appearance and Sounds, and disappears when the session ends without dismissal UI
- The active-session notice text is: “Changes apply to the next Direct Dictation session.”
- Sounds Preview disables itself while the Begin/End pair plays so repeated clicks cannot overlap playback
- Sounds Preview waits for the selected Begin sound's actual duration before playing End
- Changing the sound set stops an active preview before the next selection can play
- Direct Dictation and Sounds Preview use the existing fixed playback level; Settings has no volume preference
- The Appearance preview simulates a small bounded microphone-level loop and holds a quiet frame under Reduce Motion
- The Appearance preview always uses fixed notched MacBook reference geometry; the active HUD still adapts to its display
- Settings navigation uses a fixed Talkify blue accent; selected Glow palettes do not recolor the Settings shell

- "subtitles" was used for text displayed during a Google Meet call — resolved: this is **Live Captions**.
- HUD behavior for long drafts — resolved: the downward-growing panel won the feel test against tail-only truncation and shrink-to-fit. The HUD wraps long drafts and grows downward, capped at four lines; the other two variants remain selectable for the Settings picker.
- The voice-reactive visual — resolved: both prototyped variants ship, user-selectable from Settings, and both replace draft text while listening. The waveform (default: the Chart Line conveyor with metallic silver treatment, plus seven alternate styles) fills the visual band; the edge glow is a three-part animation — a palette-gradient beam whose bright region blooms in from under the housing on session start, sweeps the shape's open silhouette while listening, follows the voice in brightness and stroke thickness (the feel-test pick over reach, particle count, particle size, and syllable bursts), and drains back when the session ends, a one-shot ripple wave rolling across the housing at session start, and a particle cloud in the palette's colors chasing the beam's sweeping origin. The palette (Spectrum, Silver, Aurora, Sunset, Ocean, Mono) is a Settings pick coloring beam and particles together.
