# Immutable Dictation session settings snapshot

Direct Dictation captures an immutable `DictationSessionSettings` value after its target and permission guards pass, then gives that snapshot to the HUD and session sound playback. `AppSettings` remains the persisted live source for the Settings UI and Appearance preview, while changes made during an active session take effect on the next session instead of changing an in-progress visual or sound sequence.
