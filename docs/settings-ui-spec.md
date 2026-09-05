# Settings UI direction

This is a draft for discussion, based on a live inspection of Wispr Flow 1.6.399 on macOS.

## What Wispr Flow does well

- Opens Settings as a centered modal window over the main app.
- Dims the page behind the modal, which keeps the settings task focused.
- Uses a fixed left navigation rail with grouped sections: Settings and Account.
- Keeps the selected section highlighted while the right content changes in place.
- Uses a clear page title, short descriptions, and grouped rounded cards.
- Places controls at the trailing edge of each row.
- Applies changes immediately for switches and selections.
- Uses secondary actions for previews, setup, change, and customize flows.
- Uses a scrollable content area when a section is taller than the window.
- Shows destructive actions away from normal preference controls.

## Talkify mapping

| Wispr Flow pattern | Talkify version |
| --- | --- |
| General | Appearance, sound, and dictation behavior |
| System | Startup, permissions, notifications, and menu-bar behavior |
| Notetaker | Not applicable until Talkify adds recording or notes |
| Vibe coding | Not applicable |
| Connectors / MCP | Not applicable until Talkify adds integrations |
| Account | Local profile and app information, if needed |
| Plans and Billing | Not applicable for the local app |
| Data and Privacy | Dictation retention, telemetry, and reset actions |

The first Talkify release should use only sections that have real settings. Empty placeholder sections would make the app feel unfinished.

## Proposed Talkify layout

Use a black glass window with two columns:

- A 176-point left rail with a translucent black material, a small Talkify mark, and grouped navigation.
- A wider content pane with a near-black material, subtle white borders, and a scroll view.
- A selected row with a low-opacity white fill and a thin accent edge.
- Cards with a black translucent fill, a 12-point corner radius, and one-pixel white opacity borders.
- Primary text in white, secondary text in white at 55–65% opacity, and accent colors from the selected glow palette.
- Compact controls with the same dark treatment: toggles, segmented controls, menus, and buttons.

The content pane must update in place when a navigation item is selected. The selected option must also update the live HUD immediately, without a Save button.

## First sections

### Appearance

- Voice visual: Waveform, Edge Glow, Edge Glow + Draft, or Compact.
- Waveform style, shown only for Waveform.
- Glow palette, shown for Edge Glow and Edge Glow + Draft.
- Glow center, shown only for Edge Glow.
- Reveal style.
- Long draft behavior.
- Reduce Motion, using the system setting as the default.
- A live preview card that renders the selected HUD treatment.

The preview must use the same `AppSettings` instance as the HUD. Changing a picker should update both the preview and the next dictation session.

### Sounds

- Session sound set.
- Preview button that plays the selected begin/end sounds.
- Optional separate volume control later, only if the app gains volume ownership.

### Dictation

- Push-to-talk shortcut and recording behavior once those preferences exist.
- Microphone selection once Talkify exposes more than the default input device.
- Dictation language once speech recognition supports a user choice.

### Privacy and Data

- Local-only status.
- Reset preferences.
- Clear local history if history is added.
- Any telemetry switch must describe exactly what leaves the Mac.

## Component rules

Use small reusable SwiftUI components rather than a single large `Form`:

- `SettingsShellView` owns navigation and the selected section.
- `SettingsSidebarView` renders grouped navigation rows.
- `SettingsSectionView` owns the title, description, and scroll view.
- `SettingsCard` provides the dark glass card surface.
- `SettingsRow` provides the label, description, and trailing control layout.
- `SettingsPreviewCard` renders live appearance samples.

Keep `AppSettings` as the source of truth. Do not create a second draft settings model unless a future setting needs an explicit Apply/Cancel transaction.

## Verification plan

- Selecting every sidebar section changes the content pane and selected-row state.
- Appearance controls update `AppSettings` immediately.
- Conditional controls appear only for their parent visual style.
- The live preview changes when each appearance setting changes.
- Sound Preview uses the currently selected sound set.
- Settings persist after closing and reopening the window.
- Reset actions require confirmation and restore documented defaults.
- VoiceOver exposes each row label, description, and control.
- Reduced Motion removes preview animation while keeping the selected style visible.
- The window remains usable at a narrower macOS window size.

## Suggested implementation order

1. Replace the current `Form` with the two-column shell and dark glass surfaces.
2. Move the existing settings into Appearance and Sounds sections.
3. Add a live preview card backed by the existing preview harness.
4. Add tests for navigation, conditional controls, persistence, and preview state.
5. Add Dictation and Privacy sections only when their underlying settings exist.

