<p align="center">
  <img src="docs/assets/app-icon.png" width="96" alt="Talkify icon" />
  <h1 align="center">Talkify</h1>
</p>

Hold a key, speak, release — your words land in whatever you were typing. Native macOS dictation that lives in the notch, powered entirely by on-device Apple Speech. No cloud, no accounts, no telemetry.

<p align="center">
  <img src="https://img.shields.io/badge/Swift-6-orange.svg" />
  <img src="https://img.shields.io/badge/macOS-26+-blue.svg" />
  <img src="https://img.shields.io/badge/Apple%20Silicon-arm64-lightgrey.svg" />
  <img src="https://github.com/tornikegomareli/Talkify/actions/workflows/ci.yml/badge.svg" />
</p>

## Showcase

<!-- PLACEHOLDER: hero demo — hold Fn, HUD descends from the notch, speak, text lands in the focused app (GIF) -->
<p align="center">
  <img src="docs/assets/demo-dictation.gif" width="70%" alt="PLACEHOLDER — dictation demo GIF" />
</p>

<!-- PLACEHOLDER: three visuals side by side — Waveform, Edge Glow, Compact captions (GIFs or PNGs) -->
<p align="center">
  <img src="docs/assets/visual-waveform.gif" width="30%" alt="PLACEHOLDER — Waveform visual" />
  <img src="docs/assets/visual-edgeglow.gif" width="30%" alt="PLACEHOLDER — Edge Glow visual" />
  <img src="docs/assets/visual-compact.gif" width="30%" alt="PLACEHOLDER — Compact captions" />
</p>

<!-- PLACEHOLDER: Settings window and Insights charts screenshots -->
<p align="center">
  <img src="docs/assets/settings.png" width="45%" alt="PLACEHOLDER — Settings" />
  <img src="docs/assets/insights.png" width="45%" alt="PLACEHOLDER — Insights" />
</p>

## What it does

- **Direct Dictation** — hold the trigger key (fn by default), speak, release. A quick tap latches the session hands-free; Escape cancels. Finalized text inserts into the previously focused control — Accessibility insertion first, clipboard paste with restore as the fallback, with the working route remembered per app.
- **The notch HUD** — a NotchIsland-style surface that descends from the top of the display (a simulated notch on external monitors). Three voice visuals: nine waveform styles, the Edge Glow (a palette beam sweeping the silhouette, a session ripple, and a Metal-compute particle cloud), and Compact — Dynamic Island-style live captions beside a five-bar voice indicator.
- **Read Aloud** — select text in any app, press ⌥⎋ (or use the menu): Talkify speaks it with your picked Apple voice — enhanced, premium, or your Personal Voice.
- **Recordable shortcuts** — System Settings-style key recording for the dictation trigger (any single key, including bare modifiers) and the Read Aloud combo.
- **Insights** — local-only usage charts: words per day, sessions, streaks, a sixteen-week heatmap. A JSON file on your disk; nothing leaves the Mac.

## Privacy

Everything is on-device: Apple's `SpeechAnalyzer`/`SpeechTranscriber` for recognition, `AVSpeechSynthesizer` for Read Aloud. Talkify makes no network requests, stores no audio, and keeps no history beyond the local usage metrics you can see in Insights.

## Requirements

- macOS 26 (Tahoe) on Apple Silicon
- Permissions on first run: Microphone, Speech Recognition, Accessibility, Input Monitoring — dictation reads keys globally and inserts text into other apps, which is exactly what those two grants exist for.

## Install

With Homebrew:

```bash
brew tap tornikegomareli/talkify https://github.com/tornikegomareli/Talkify
brew install --cask talkify
```

Or grab [**Talkify.dmg**](https://github.com/tornikegomareli/Talkify/releases/latest/download/Talkify.dmg) from the latest release.

Build from source:

```bash
git clone https://github.com/tornikegomareli/Talkify.git
cd Talkify
open Talkify.xcodeproj   # ⌘R
```

Or headless:

```bash
xcodebuild -project Talkify.xcodeproj -scheme Talkify -configuration Debug build
```

Run the tests the same way CI does:

```bash
xcodebuild test -project Talkify.xcodeproj -scheme Talkify -destination 'platform=macOS'
```

## Using it

| Action | Gesture |
|---|---|
| Dictate | Hold **fn**, speak, release |
| Hands-free session | Quick-tap **fn**, speak, tap again to finish |
| Cancel mid-session | **Esc** |
| Read selected text aloud | **⌥ ⎋** (toggles; also in the menu) |
| Everything else | Menu bar ghost → Settings |

The trigger and the Read Aloud shortcut are rebindable in **Settings → Shortcuts** — click the recorder, press the key you want.

## Architecture

Modules as folders, one-directional callbacks wired in the composition root, and a pure reducer where the state is genuinely hairy:

- `App/` — composition root, settings store, status item
- `Input/` — the global key event tap and recorded bindings
- `Dictation/` — the session machine (`DictationSessionMachine`, a pure tested reducer) and the speech/insertion services
- `HUD/` — geometry seams, the shell, the voice visuals, and all Metal shaders
- `ReadAloud/`, `Settings/`, `Insights/`

`CONTEXT.md` is the domain rulebook; decisions live in `docs/adr/`. Code style: 2-space indentation, enforced by `.editorconfig`.

## Roadmap

- **Live Captions & Meeting Transcripts** — ephemeral captions from a selected app's audio (Chrome, YouTube, meeting apps), and the saved, timestamped transcript as a separate action. The domain design already lives in `CONTEXT.md`; the recognition pipeline is ready for non-microphone audio.
- **Text cleanup** — optional on-device polishing of dictated text (fillers, punctuation) once the raw-insertion core is benchmarked. Version 1 deliberately inserts exactly what you said.
- **Snippets** — saved text blocks inserted by a spoken trigger word: say your trigger mid-dictation and the whole block lands instead.

## Contributing

PRs welcome. `main` is protected — changes come in through a pull request with green CI (build + full test suite on macOS). Read `CONTEXT.md` first: its terminology is binding, and a few visuals are feel-tested picks that shouldn't be "fixed" casually.

## Pre-release caveats

Two bundled assets are development-only and will be replaced before any binary release: the **Pop** sound set (CC-BY-NC, see `Talkify/Resources/Sounds/LICENSE-SOUNDS.txt`) and the **Siri orb** prototype artwork (unlicensed, see `LICENSE-ARTWORK.txt`). Both are excluded from release builds' Settings.

## License

<!-- PLACEHOLDER: pick a license before publishing (MIT/Apache-2.0/GPL) and add the LICENSE file -->
TBD.
