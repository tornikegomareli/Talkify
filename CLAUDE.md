# Talkify

Menu-bar-only macOS 26 dictation app (Apple Silicon only). Read `CONTEXT.md` first — it is the domain model and rulebook; its terminology is binding. ADRs live in `docs/adr/`.

## State of the repo

The old Tuist project was deleted on purpose. The app is being rebuilt from scratch as a plain committed `Talkify.xcodeproj` (no Tuist, no generation). Nothing buildable exists yet.

## Stack decisions (already made, do not relitigate)

- Plain `Talkify.xcodeproj`, Swift 6, strict concurrency complete
- AppKit is the shell: lifecycle, status item, non-activating panels
- SwiftUI for windowed UI (settings, onboarding), hosted in the AppKit shell
- Apple Speech only (`SpeechAnalyzer`/`SpeechTranscriber`), no Whisper, no third-party dependencies
- Scaffolding values (bundle ID, entitlements, signing, Info.plist keys): `CarryOver/ProjectSettings.md`

## CarryOver/

`CarryOver/` holds the six proven components from the previous implementation plus helpers. They encode hard-won behavior (session prewarming, gesture latching, per-app insertion routes, clipboard restore). Move them into the new project as-is; do not rewrite them:

- `SpeechRecognitionService.swift` — actor around SpeechAnalyzer; prewarms sessions
- `MicrophoneInput.swift` — AVAudioEngine tap → AsyncStream<AnalyzerInput>
- `TextInsertionService.swift` — AX insertion first, paste fallback, route memory
- `DictationTriggerMonitor.swift` — CGEventTap for Fn (keycode 63) and Escape
- `DirectDictationController.swift` — the session state machine (idle/starting/recording/finishing/cancelling, held vs latched)
- `PermissionService.swift`, `NSScreen+DisplayID.swift`

Known cleanup when integrating: strip the `[DEBUG-fn8b]` OSLog lines (leftover Fn-key diagnosis). `DirectDictationController` references `DictationHUDController`, which was deliberately not carried over — the HUD is being rebuilt (see below).

## The HUD rebuild

The old bottom-fallback HUD is superseded. Per CONTEXT.md and ADR-0001: the HUD always descends from the top center; non-notch displays get a simulated notch. The reference implementation to lift patterns from is Tilebar's NotchIsland module:

`/Users/tgomareli/Development/work/Tilebar-dev/Tilebar/Tilebar/Tilebar/Modules/NotchIsland/`

Reading order: `Domain/NotchGeometry.swift` → `Domain/NotchIslandMetrics.swift` → `UI/NotchIslandShellView.swift`. Key patterns: fixed-size host window (origin moves, never resizes), measured-vs-simulated notch split, fillets only on a real housing, interactive-rects hit testing, `NSWindow.Level.mainMenu + 3` (no private APIs).

Two HUD decisions are deliberately open and must be prototyped, not decided in code review (see CONTEXT.md flagged ambiguities): long-draft behavior (3 variants) and the voice-reactive visual (Metal shader waveform vs notch-edge glow).

## Roadmap order

1. Scaffold xcodeproj + shell (status item, app delegate) and wire in CarryOver files
2. NotchIsland-style HUD surface
3. Prototype the two flagged HUD variants, pick by feel
4. Insertion latency benchmark — CONTEXT.md gates all other features on it

## Agent skills

### Issue tracker

Issues live in GitHub Issues at tornikegomareli/Talkify (`gh` CLI). See `docs/agents/issue-tracker.md`.

### Triage labels

Default names: needs-triage, needs-info, ready-for-agent, ready-for-human, wontfix. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.
