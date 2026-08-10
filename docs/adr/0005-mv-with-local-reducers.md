# MV with local reducers — no MVVM, no TCA

Talkify's UI layer stays model–view: `@Observable` models (`AppSettings`,
`DictationHUDContent`, `UsageTracker`, `VoiceCatalog`) bound directly by
SwiftUI views, with AppKit controllers doing orchestration and all
cross-module wiring in `App/`. We do not adopt MVVM (view models forwarding
observable bindings add indirection without testability here) and we do not
adopt TCA or any architecture dependency.

Where state transitions are genuinely hairy, that logic is extracted into a
**local pure reducer** — a value type with `reduce(Action) -> [Effect]`, no
clocks, no services — owned and driven by its controller. The first and
motivating case is `DictationSessionMachine`: the session lifecycle
(idle/starting/recording/finishing/cancelling), quick-tap latching,
finish-queued-while-starting, cancel-while-starting, and the no-speech
policy, all previously untestable behind live microphone and AX access.

## Rules

- A reducer is added only where an enum state machine with real races
  already exists — not per feature, not per screen.
- Reducers are pure and synchronous: instants and results arrive inside
  actions; async work happens in the controller, which feeds completions
  back as new actions.
- Effects are data (an enum); the controller is the only interpreter.
- Simple binding surfaces (Settings panes, Insights charts) stay plain MV.

## Consequences

- `DirectDictationController` shrinks to guards + effect execution; every
  gesture/race rule is pinned by `DictationSessionMachineTests`.
- Future candidates (a captions engine, queued Read Aloud) follow the same
  shape if and when their state grows real transitions.
- Architecture reviews should not re-suggest MVVM or a global store; this
  ADR records why.
