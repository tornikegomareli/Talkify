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

## Relationships

- Pressing the **Dictation Trigger** starts **Direct Dictation** immediately
- The default **Dictation Trigger** is Fn and onboarding lets the user change it
- Releasing a held **Dictation Trigger** ends **Direct Dictation** and inserts its text
- Releasing the **Dictation Trigger** before 250 milliseconds counts as a quick tap
- A quick tap leaves **Direct Dictation** active until the next trigger press
- The **Direct Dictation** HUD shows live draft text while speech continues
- The HUD renders volatile recognition results immediately
- **Direct Dictation** inserts only finalized recognition results
- The **Direct Dictation** HUD expands from the physical notch on the focused input's display
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
- Talkify persists only application settings; macOS manages permission state
- Settings lets the user choose the session sounds, the voice-reactive visual, and the waveform style
- Insertion latency must be benchmarked before choosing permanent per-application defaults
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

- "subtitles" was used for text displayed during a Google Meet call — resolved: this is **Live Captions**.
- HUD behavior for long drafts — resolved: the downward-growing panel won the feel test against tail-only truncation and shrink-to-fit. The HUD wraps long drafts and grows downward, capped at four lines; the other two variants remain selectable for the Settings picker.
- The voice-reactive visual — resolved: both prototyped variants ship, user-selectable from Settings. The waveform (default: the Chart Line conveyor with metallic silver treatment, plus seven alternate styles) replaces draft text while listening; the edge glow (a static silver comet sweeping the shape's open silhouette) keeps draft text in the middle.
