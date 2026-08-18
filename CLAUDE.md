# Talkify

Menu-bar-only macOS 26 dictation app (Apple Silicon only).

Read these three before you write anything. All three are binding.

1. **[`CONTRIBUTING.md`](CONTRIBUTING.md)** is the contract: how issues gate work,
   code style, tests, commits, pull requests, merging, AI usage, licensing. Every
   rule in it applies to you. Where this file and that one disagree, that one wins.
2. **[`CONTEXT.md`](CONTEXT.md)** is the domain model. Its terminology is binding:
   Direct Dictation, Dictation Trigger, Drop Target, Staged transcript. Use the
   term it lists and avoid the ones it says to avoid, in identifiers, comments and
   commit messages alike.
3. **[`docs/adr/`](docs/adr/)** holds the architectural decisions. If your change
   contradicts one, say so in the issue instead of overriding it in silence.

## The four rules that get broken most

Restated here on purpose, because agents follow pointers unreliably. These are
copies. `CONTRIBUTING.md` is canonical; if you edit one, edit both.

- **Two spaces for indentation**, everywhere, in Swift and Metal alike. Never
  reformat back to four.
- **No `// MARK:` comments.** A file that needs section markers needs splitting.
- **Pull requests: `[TAG] What it does` for the title**, one of `[FEATURE]`,
  `[FIX]`, `[REFACTOR]`, `[DOCS]`, `[TEST]`, `[CHORE]`, matching the branch
  prefix. The description is a few sentences (what, how, why) plus `Closes #N`.
  No bullets, no headings, no test plan, no diff summary.
- **Never attribute a pull request to an agent.** No "Generated with" line, no
  robot emoji. The person who opened it is the author.

## State of the repo

Buildable and working end to end: hold Fn, speak, release, and the text lands in
the previously focused control. Milestone 1 (shell plus Direct Dictation) and the
HUD prototyping phase are shipped. Every decided-by-feel pick (reveal animation,
long-draft behaviour, both voice visuals) ships as an `AppSettings` preference
behind the Settings window.

Build and test commands are in `CONTRIBUTING.md`. Both must pass before you hand
work back.

## Stack decisions (already made, do not relitigate)

- Plain committed `Talkify.xcodeproj` (no Tuist, no generation), Swift 6, strict
  concurrency complete
- AppKit is the shell: lifecycle, status item, non-activating panels
- SwiftUI for windowed UI (Settings, onboarding), hosted in the AppKit shell
- Apple Speech only (`SpeechAnalyzer`/`SpeechTranscriber`), no Whisper
- Exactly one third-party dependency: Sparkle, for self-updating, quarantined
  behind `Talkify/Updates/SparkleUpdaterService.swift`. Adding a second is a
  decision to raise, not to make.
- Scaffolding values (bundle ID, entitlements, signing, Info.plist keys):
  `docs/ProjectSettings.md`

## Layout (modules as folders; communication is one-directional callbacks wired in App/)

- `Talkify/App/` — the composition root: `AppDelegate` (wires every controller, owns the key-binding observation loop), `StatusItemController` (menu + blinking ghost), and `AppSettings.swift` — every user preference, one observable UserDefaults-backed store. The key strings and enum rawValues are load-bearing (stored picks; sound-asset name prefixes) — do not rename.
- `Talkify/Input/` — the global CGEvent tap (`GlobalKeyEventMonitor`: dictation trigger, cancel, and Read Aloud shortcut) and the recorded `KeyBinding` model, shared by Dictation, Settings, and the status menu.
- `Talkify/Dictation/` — the session core and its proven components (session prewarming, gesture latching, focus-validated paste insertion, guarded clipboard restore). `DictationSessionMachine` is the pure reducer holding every state transition (idle/starting/recording/finishing/reviewing/cancelling, held vs latched) — fully covered by `DictationSessionMachineTests`; `DirectDictationController` runs the begin guards and executes its effects (ADR-0005: MV + local reducers, no MVVM, no TCA). The `reviewing` state is the **Editable Draft** variant: the draft stays in the HUD until Return pastes, the trigger starts a **Replacement Dictation** round, or Escape discards (the terms and rules live in `CONTEXT.md`). `HUD/` holds everything only dictation draws: its shell view, its content model, and `Visuals/` the voice visuals with their styles, palettes and tokens.
- `Talkify/DropTranscription/` — dragging a media file at the notch: `DragWatcher`/`DropZone` (the gesture), `FileTranscriptionService` (its own analyzer, sharing nothing with dictation's prewarmed one), `StagedTranscript`/`TranscriptDestination` (where a transcript lives and lands), `TranscriptOffer` (the card's whole life — countdown, drag, copy, expiry), and `HUD/` its four state views plus their controller.
- `Talkify/CoreHUD/` — **only what both features share**: `HUDStage` owns the one panel and arbitrates who holds the shape; `HUDSurface` draws the black shape, its fillets and its reveal; plus the sounds, the pure geometry seams (`HUDPlacement`, `HUDNotchGeometry`, tested) and `Shaders/` (ADR-0002; they compile into one Metal library whatever folder they sit in, so they stay together). Anything one feature alone draws belongs in that feature's `HUD/`. Canvas previews live next to the views; the harness uses a volatile defaults suite.
- `Talkify/ReadAloud/` — speaking selected text: controller, `VoiceCatalog`, and the read-only `FocusedSelectionReader` (never touches insertion).
- `Talkify/Settings/` — the borderless Settings window: shell (`SettingsView`), navigation model (`SettingsSections`), `Sections/` one file per pane, `Components/` the reusable design system (`SettingsTheme/Card/Row/PickerRow/ButtonStyle`, key recorder, drag handle).
- `Talkify/Updates/` — Sparkle, wrapped so nothing else imports it: the appcast is a static file in the repo, updates are EdDSA-verified, and the activation policy flips for Sparkle's windows because they misplace themselves under `LSUIElement`.
- `Talkify/Insights/` — local usage metrics (pure `UsageMetrics`, tested), store, tracker, and the Swift Charts section.
- `Talkify/Resources/Sounds/` — sound sets. **Pop is CC-BY-NC and must be replaced or dropped before any release**; see `LICENSE-SOUNDS.txt`.
- `Talkify/Assets.xcassets/Siri/` — the Siri-orb prototype artwork (voice visual under feel test). **Unlicensed, imitates Apple's Siri orb, must be replaced or dropped before any release**; see `LICENSE-ARTWORK.txt`.

## HUD rules that keep biting

- Fixed-size host window: origin moves, never resizes (`HUDNotchGeometry.windowFrame` is sized for the tallest layout).
- Fillets only against a real housing; simulated notch (185×32) elsewhere. `NSWindow.Level.mainMenu + 3`, no private APIs.
- Reveal bounce lives only in top-anchored scale, never position — a position overshoot opens a gap against the screen edge.
- Silence and a dead microphone must look different (watchdog flips visuals to a static amber state).

## Where to put a test

Test the pure seams: `DictationSessionMachine`, `HUDPlacement`, `HUDNotchGeometry`,
`UsageMetrics`, `KeyboardMap`. They are pure so their rules can be pinned without a
microphone or a window. When a bug turns out to live in impure code, the fix is
usually to move the rule into a value type and test that, not to mock the world.

## Roadmap

1. ~~Scaffold + wire CarryOver~~ done
2. ~~NotchIsland-style HUD surface~~ done
3. ~~Prototype the flagged HUD variants~~ done — all variants ship as Settings options
4. **Insertion latency benchmark — next; CONTEXT.md gates all other features on it**

## Agent conventions

`AGENTS.md` is a symlink to this file, so both tool families read the same rules.
Edit `CLAUDE.md`; the symlink follows.

- **Issue tracker.** GitHub Issues at tornikegomareli/Talkify, via the `gh` CLI.
  See `docs/agents/issue-tracker.md`. Work is gated by triage label: see
  `CONTRIBUTING.md` for which labels mean you can start.
- **Triage labels.** needs-triage, needs-info, ready-for-agent, ready-for-human,
  wontfix. See `docs/agents/triage-labels.md`.
- **Domain docs.** Single-context: `CONTEXT.md` plus `docs/adr/` at the repo root.
  See `docs/agents/domain.md`.
