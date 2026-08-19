# Input method spike (throwaway)

Answers one question for the live-insertion idea: can a third-party input
method put system-dictation-style provisional text into an arbitrary app's
field, chunk by chunk, and what does it cost.

Not Talkify. Shares no code with Talkify. Built to be installed, tried in a few
apps, read, and deleted.

## Build and install

    ./spike/ime/build.sh          # build, install to ~/Library/Input Methods/
    ./spike/ime/build.sh --clean  # remove it

Then **log out and back in**. See "What blocked the measurement" below.

Then System Settings > Keyboard > Input Sources > Edit > + > English >
"Talkify IME Spike", switch to it in the menu bar, and press **F13** in any
text field.

Watch it work:

    log stream --predicate 'eventMessage CONTAINS "[IMESpike]"'

F13 plays a scripted dictation: three growing marked-text revisions 450ms
apart, then a commit. Every other key passes straight through, which is what an
input method must do or typing breaks system-wide.

## What is verified

- `IMKServer` starts and registers the connection: `server up as com.talkify.imespike`
- The `@objc(TalkifySpikeController)` class is in the binary under the exact
  name `InputMethodServerControllerClass` names, checked with `otool -ov`
- The bundle signs and validates under both ad-hoc and the real Developer ID

## What blocked the measurement

The input source never entered the system database in-session. Tried, in order,
all of which failed to make it appear in `TISCreateInputSourceList(nil, true)`
alongside the other 318 installed sources:

- ad-hoc signature
- real Developer ID signature with hardened runtime
- `TISRegisterInputSource(bundleURL)`, which returns `noErr` and changes nothing
- adding `tsInputMethodCharacterRepertoireKey` and the per-mode repertoire key

That points at the database only being rescanned at login, which matches what
IME developers report. It is not a blocker for the feature, but it is a cost
worth writing down: **installing an input method is a logout, not a prompt.**
Nothing Talkify does today asks the user to log out.
