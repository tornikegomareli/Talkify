# MyVoice Integration

## Dependency approach — vendored source integration

MyVoice's standalone package (`MyVoice/Sources/MyVoice/`) is complete and
tested (57/57), but Talkify has no sibling `MyVoice` directory in CI or in
the isolated worktrees this project uses (see treehouse paths and
`no-mistakes` detached HEADs). Adding a local Swift Package dependency
`../myvoice/MyVoice` would couple the Xcode project to a filesystem layout
that only exists on one developer's machine and would require editing
`project.pbxproj`'s `XCRemoteSwiftPackageReference` to a local reference that
breaks when the package lives elsewhere.

This integration therefore **vendors the capture path** into
`Talkify/Dictation/MyVoice/`:

- `MyVoiceRecord.swift`
- `MyVoiceStorage.swift`
- `MyVoiceAudio.swift`
- `MyVoiceCollector.swift`

are copied verbatim from `MyVoice/Sources/MyVoice/` with a one-line
`// Vendored from …` header. The fifth file,
`MyVoiceCaptureService.swift`, is Talkify's thin bridge: it defines the
`MyVoiceCaptureServicing` protocol and a production `MyVoiceCaptureService`
that gates on `myvoiceCaptureEnabled` and empty checks, then dispatches to
`MyVoiceCollector` via `Task.detached(priority: .utility)` so the insertion
path never blocks. `DirectDictationController` owns a
`myVoiceService: MyVoiceCaptureServicing` injected via `init` (default live
`MyVoiceCaptureService(enabled: { true })`, gated by the controller's
`session.myvoiceCaptureEnabled`); tests inject fakes through the same seam.

Future updates to the standalone package are ported by copying the four
vendored files again — the diff is then exactly the contract change, with
no package.resolved noise.

Alternative considered: local Swift package dependency. Rejected for the
isolation/CI reason above; vendoring keeps the Xcode project using its
existing `PBXFileSystemSynchronizedRootGroup` (any file in `Talkify/` is
automatically a member of the `Talkify` target, no `project.pbxproj` edit)
and leaves the contract identical to the standalone package.

No network or training path was added.

## Settings

`AppSettings.myvoiceCaptureEnabled: Bool`, `UserDefaults` key
`myvoiceCaptureEnabled`, default `false`. Off-by-default and privacy-clear:
Settings → Appearance (HUD branch; Dictation on `main`) shows

> Save dictation samples — Saves completed dictations as local samples with
> raw ASR transcription and corrected text in
> `~/Library/Application Support/Talkify/MyVoice/`. Off by default — nothing
> is kept until you turn this on, and samples never leave this Mac.

The flag is captured into `DictationSessionSettings` at session start
(ADR-0004), so a mid-session toggle applies next session.
`MyVoiceCaptureService.capture` skips when Off or when the trimmed raw
transcript is empty; empty transcripts never create candidates.

## Commit points

- `DirectDictationController.finishRecognition(speakingDuration:)` —
  `speechService.finish()` returns `rawTranscript` (`startedAt` captured at
  `beginRecognition`, `stoppedAt` right after `finish`). For `pasteOnRelease`
  (`draftStyle == .pasteOnRelease`), after `textInsertionService.insert` and
  `usageTracker.recordSession`, if `session.myvoiceCaptureEnabled` and
  `!trimmedRaw.isEmpty`, call `myVoiceService.capture(rawTranscript: text,
  correctedText: text, audioURL: nil, startedAt: startedAt, stoppedAt:
  stoppedAt, localeIdentifier: locale)` — transcript-only candidate.

- `DirectDictationController.pasteDraft()` — HUD editable-draft Return.
  `pendingRawTranscript` is set at `finishRecognition` when entering
  `editableDraft` (`pendingRawTranscript = text` if nil, preserving the
  immutable raw across replacement rounds). At Return, `raw =
  pendingRawTranscript ?? hudController.draftText`, `corrected =
  hudController.draftText`, then after `insert` and usage, the same gated
  `myVoiceService.capture(raw, corrected, nil, startedAt, Date(), locale)`.
  `pendingRawTranscript` and `myVoiceSessionStartedAt` are cleared via
  `.notifyRecording(false)` or after `pasteDraft`. Direct
  `MyVoiceCollector.collect(rawTranscript:correctedText:)` tests prove
  `asr.txt` immutable and `corrected.txt` equal to the HUD draft; the
  storage enforces `correctedText.isEmpty ? raw : corrected`.

## Audio limitation

**Transcript-only in this slice.** The existing `MicrophoneInput` tap at
`installTap(onBus: 0)` feeds `AVAudioConverter` → `AnalyzerInput`; the
integration doc specifies teeing that *converted* buffer stream rather than
installing a second tap. Teeing adds `AVAudioFile` lifecycle across
`start(outputFormat:)`, `receive(buffer:converterBox:)`,
`finalizeRecording()`, and `cancel()` on every failure/cancellation path.
That touches the HOT PATH and expands scope without additional tests.

Candidates are therefore created with `audioURL == nil`, stored as
`audio/source.caf` absent, `audio.sha256 == emptySHA256`
(`e3b0c44298fc1c149afbf4c8996fb924…`), `format: caf`, `sampleRate: 16000`,
`channels: 1`, `durationMs: wall-clock`. This is allowed by
`MyVoiceStorage.validateStaged` (missing audio file is allowed only when sha
is empty) and exercises the same `tmp → validate → rename → event` path as
real audio; adding the tee later keeps that path and fills a real file.

## Failure contract

- `finishRecognition` `throw` (recognition failure) — no capture, message shown.
- Insertion outcome `.unavailable` — a non-empty transcript is still captured: the sample is the words, not their delivery.
- Cancellation (`.cancelPressed`, `.cancelRecognition`) — no capture, `myVoiceSessionStartedAt` cleared via `.notifyRecording(false)`.
- Empty/whitespace `text` — skipped (`trimmedRaw.isEmpty`).
- `MyVoiceStorage` throw (`ENOSPC` via `setNextCommitShouldFail`, sha mismatch) —
  `tmp` cleaned, no `samples/<id>/`, insertion already completed because
  capture runs detached after `insertText`. `os_log` on failure via `Logger`
  `com.talkify.myvoice`.

## Tests

- `TalkifyTests/MyVoiceCaptureTests.swift` — controller seam + storage seam:
  Off-is-default, UserDefaults round-trip, Off-no-sample-with-insert,
  On-creates-candidate-with-raw-and-corrected, empty/whitespace skipped,
  cancellation/failure no sample, collector failure not blocking insertion,
  session-snapshot isolation, direct `MyVoiceCollector` candidate with
  `asr.txt`/`corrected.txt`/`events.jsonl`, editable-draft `asr != corrected`
  via direct collector, disk-full cleans `tmp`.
- Run: `xcodebuild test -project Talkify.xcodeproj -scheme Talkify -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`
