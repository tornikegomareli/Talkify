# Contributing to Talkify

Talkify is a menu-bar-only dictation app for macOS 26 on Apple Silicon. It is
maintained by one person in their spare time. This guide is the contract for
everyone who writes code here, human or agent. `CLAUDE.md` and `AGENTS.md` point
at this file and it wins over both.

Read [`CONTEXT.md`](CONTEXT.md) before you write anything. It is the domain model
and the rulebook, its terminology is binding, and most review comments here are
some version of "that is not what CONTEXT.md says".

## Read the room

The one rule that covers what the rest of this file spells out. Before you change
anything, read the code around it. Match the naming, the comment density, the file
size, the test style, and the way decisions are recorded. A patch that argues with
the surrounding code is a patch that gets sent back, even when it is correct.

## Before you write code

**Open an issue first.** Discussions are off, so
[Issues](https://github.com/tornikegomareli/Talkify/issues) are the only channel:
bugs, features and questions all start there.

A pull request implements an issue. A pull request that arrives with no issue
behind it may be closed or left to go stale, however good the code is. This is not
about gatekeeping. It is that design belongs in the issue, where it is cheap to
change, and a pull request is a bad place to discover that a feature is not wanted.

The flow, with the labels the tracker actually uses:

| Label | What it means | Can you start? |
| --- | --- | --- |
| `needs-triage` | The maintainer has not evaluated it yet | No |
| `needs-info` | Waiting on the reporter | No |
| `ready-for-agent` | Fully specified, an agent could take it unattended | Yes |
| `ready-for-human` | Specified, but needs human judgement or hardware | Yes |
| `wontfix` | Decided against | No |

Search before you post. Add a reaction to an existing issue instead of a "+1"
comment. Comment only when you have something to add, such as a reproduction, a
diagnosis, or a case the issue does not cover.

### What a bug report needs

Talkify sits on top of the window server, the Accessibility API and a global event
tap, so "it did not work" is never enough to act on. Include:

- macOS version and Mac model, and whether the display has a physical notch
- Talkify version, from the status menu
- The trigger you used and whether it was held or quick-tapped
- The application you dictated into
- What you expected and what happened instead
- A screen recording, for anything about the HUD, its animation or its placement
- Console output filtered to Talkify, for a crash or a hang

### What a feature request needs

- The case you are trying to solve, not the solution you have in mind
- How you work around it today
- What other dictation or speech apps do here, if anything
- Which of the terms in `CONTEXT.md` it touches, or that it needs a new one

Features that contradict a decision in `docs/adr/` or a rule in `CONTEXT.md` need
to argue with that decision explicitly. See [Decisions already
made](#decisions-already-made).

## AI usage

Talkify is built with AI assistance and welcomes it. The rules are about
comprehension, not about tooling.

**Disclose it.** Say which tool you used and how much of the work it did. A line in
the pull request is enough.

**Understand what you submit.** You must be able to explain every line of your
change, why it is written that way, and what happens at its edges, you can use AI to explain code to you, you can use AI to get more understanding but most important is that you need to understand what code you ship, because this code need to be maintained in the future. If a reviewer asks why a guard is there and the
honest answer is "the agent put it there", the change is not ready. Submitting
output you have not read moves the work of finding its bugs onto the maintainer.

**Text and code only.** Do not submit generated images, icons, audio or video.

**Run it.** A change to dictation, the HUD, insertion or Read Aloud needs to have
been used on a real Mac, not only compiled. Say in the pull request what you
tested and on what hardware. If you cannot test a path, say which one and why.

Ignoring this gets pull requests closed. Repeatedly ignoring it gets them closed
without a review.

## Building and testing

You need macOS 26 on Apple Silicon, and Xcode.

```bash
git clone https://github.com/tornikegomareli/Talkify.git
cd Talkify
open Talkify.xcodeproj   # ⌘R
```

Headless, which is what CI runs:

```bash
xcodebuild -project Talkify.xcodeproj -scheme Talkify -configuration Debug build
xcodebuild test -project Talkify.xcodeproj -scheme Talkify -destination 'platform=macOS'
```

Both must pass before you open a pull request. Four media tests skip without their
fixtures; that is expected and happens on `main` too.

Talkify needs Microphone, Speech Recognition and Accessibility permission to run.
A debug build asks for its own, separate from a released copy.

## Code style

These are rules, not preferences.

- **Two spaces for indentation.** Everywhere: Swift, Metal, JSON, YAML. Indent
  width 2, tab width 2, spaces not tabs. This matches the committed
  `.editorconfig`. Never reformat a file back to four spaces.
- **No `// MARK:` comments.** A file that needs section markers is a file that
  needs splitting. Use small types and separate files instead.
- **Use the vocabulary in `CONTEXT.md`.** It lists the term to use and the terms to
  avoid. Write Direct Dictation, not voice typing. Write Dictation Trigger, not
  hotkey. This applies to identifiers, comments, commit messages and UI strings.
- **Comment why, not what.** The comments in this codebase explain the reason a
  line survives review: which race it closes, which platform behaviour forced it.
  Read a few in `GlobalKeyEventMonitor.swift` before writing your own.
- **Keep the surface small.** No abstraction for a single caller, no configuration
  nobody asked for, no error handling for states that cannot happen.

### Tests

Put tests next to their peers in `TalkifyTests/`, named after the behaviour rather
than the function: `releasingRightOptionWhileLeftIsHeldReadsAsUp`, not `testFlags`.

Test the pure seams. `DictationSessionMachine`, `HUDPlacement`,
`HUDNotchGeometry`, `UsageMetrics` and `KeyboardMap` are pure on purpose so their
rules can be pinned without a microphone or a window. When a bug turns out to live
in impure code, the fix is usually to move the rule into a value type and test that.

A bug fix comes with a test that fails before it.

## Branches

Name a branch `type/short-description`, in lower case, with words separated by
hyphens:

```
feature/drop-transcription
fix/drop-target-sticks-while-dragging
docs/drop-transcription-readme
chore/versioned-dmg
```

The type is one of six. It is the same word as the tag on the pull request title,
so a branch and its pull request always agree:

| Branch prefix | Pull request tag | For |
| --- | --- | --- |
| `feature/` | `[FEATURE]` | New behaviour a user can see |
| `fix/` | `[FIX]` | A bug, a crash, a race, a flaky test |
| `refactor/` | `[REFACTOR]` | Changes shape, keeps behaviour |
| `docs/` | `[DOCS]` | Documentation and comments only |
| `test/` | `[TEST]` | Tests only |
| `chore/` | `[CHORE]` | Build, CI, release, tooling, dependencies |

Describe the change, not the ticket: `fix/hud-stutters-on-reveal`, never
`fix/issue-42`. Do not use `bugfix/`, and do not leave your tool's default branch
name such as `agent/...` or `codex/...`. Work on a branch, never on `main`.

## Pull requests

**Title it `[TAG] What the change does`**, using the tag from the table above:

```
[FEATURE] Allow mouse buttons to trigger dictation
[FIX] Keep the drop target open while the pointer is still on it
[DOCS] Put Drop Transcription in the README
```

One tag, in square brackets, upper case, at the front. After it, write the change
in the imperative, as a sentence without a full stop. The title survives the merge
as the commit subject on `main`, so write it for someone reading `git log` in a
year.

**Link the issue in the body.** If the pull request implements an issue, and it
should, put the reference on its own line at the end:

```
Closes #42
```

Use `Closes #42` when merging the pull request should close the issue, which is
the normal case. Use `Refs #42` when it is related but does not finish the work.
This one line is the only exception to the "nothing else" rule below.

**Descriptions are small and concrete.** A few sentences answering what, how and
why. Nothing else.

- No bullet lists, no headings, no test-plan section, no caveats section, no
  summary of the diff
- **Never claim the pull request was generated by an agent.** No "Generated with"
  line, no robot emoji, no tool attribution. Disclose AI usage in your own words
  instead, as described above. The person opening the pull request is its author

**One pull request, one concern.** Unrelated cleanups belong in their own pull
request. If you notice dead code while working, mention it in the issue rather than
deleting it in passing.

**Do not reformat code you are not changing.** A diff where every changed line
traces back to the stated purpose is a diff that can be reviewed.

## Commits and merging

**Commit messages** say what the commit does, in the imperative, on one line where
that is enough. They carry no `[TAG]`; the tag belongs to the pull request title.
Look at `git log` before writing one.

- **Squash by default.** A branch that iterated, with prototypes, review fixes or a
  merge from another branch, becomes one commit on `main`.
- **Rebase only when the commits are already atomic**, meaning each one builds,
  passes and is a change someone might want to land on its own. The test is
  `git bisect`: if a regression would be easier to find at one of these commits
  than in the whole branch, keep them.
- Either way `main` stays linear. Branch protection enforces it.

## Decisions already made

These are settled. Reopening one needs a new argument, not a preference:

- A plain committed `Talkify.xcodeproj`. No Tuist, no project generation
- Swift 6, strict concurrency complete
- AppKit is the shell: lifecycle, status item, non-activating panels. SwiftUI
  renders windowed UI inside it
- Apple Speech only, `SpeechAnalyzer` and `SpeechTranscriber`. No Whisper, no
  local inference models
- Model-View with local pure reducers. No MVVM, no TCA, no global store
  (`docs/adr/0005-mv-with-local-reducers.md`)
- Exactly one third-party dependency, Sparkle, confined to `Talkify/Updates/`.
  Adding a second is a decision to raise, not one to make in a pull request

Architectural decisions live in [`docs/adr/`](docs/adr/). If your change
contradicts one, say so in the issue and say why it is worth reopening. If your
change makes a new decision of that size, add an ADR alongside it.

## Licensing

Talkify is [MIT](LICENSE). Opening a pull request licenses your contribution under
the same terms and allows the maintainer to modify it.

## Working as or with an agent

`CLAUDE.md`, and `AGENTS.md` which is a symlink to it, orient an agent in this
codebase: the module map, the traps that keep biting, the current roadmap. They
name this file as binding and do not repeat it, apart from four rules restated
there because they are the ones agents break most.

Repo-specific agent conventions live in [`docs/agents/`](docs/agents/): how the
issue tracker is used, what the triage labels mean, and how the domain docs should
be read. An agent working here should read those, `CONTEXT.md`, and this file.

Everything above applies to work an agent did on your behalf. You opened the pull
request, so it is yours to explain.
