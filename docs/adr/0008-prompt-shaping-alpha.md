# Prompt shaping alpha

Direct Dictation gains an alpha prompt shaping pass: while the setting is
on, the selected prompt from a fixed library rewrites finished dictation
text between recognition finish and insertion, through FoundationModels'
`LanguageModelSession` with a fresh session per rewrite. The feature is
alpha-gated and off by default, so the default session still inserts raw
finalized text. Passthrough is the rule on every failure path: model
unavailability, an error, a refusal, an empty answer, or a slow answer all
insert the raw words unchanged. The slow-answer path is a 10 second
timeout of our own, because on macOS 26 the framework offers no request
timeout of its own.

Shaping stays on-device only. That is consistent with the app's standing
Apple-frameworks, no-network story: FoundationModels is an Apple system
framework, not a dependency, so the one-third-party-dependency rule and
the nothing-leaves-the-Mac promise both hold.

The library is fixed rather than free-form. An alpha exists to test the
feel of shaped insertion at all; user-authored prompts are a later
decision, taken only if the feel test earns it.

The transcript is framed as data, never as the conversational prompt. An
instruction-tuned model handed a bare transcript as its user turn answers
a question-shaped one — "what time does the meeting start tomorrow" comes
back answered instead of cleaned. So the invariant framing lives in the
session's instructions, which the model weighs over prompt content: the
user turn is always a raw transcript to transform, wrapped in explicit
`<transcript>` markers, and each library prompt carries a one-shot
example whose input is question-shaped and whose output rewrites it
unanswered, because the example carries that rule better than any
sentence stating it.

Ordering is deliberate: transcription history writes before shaping runs,
so history is always the words as spoken, never the model's rewrite.

When the model is unavailable, the notice is a persistent line in
Settings beside the alpha toggle, not a HUD message. The HUD dismisses
itself after about two seconds and the moment of failure is mid-insertion,
so a HUD notice would vanish before it could be read; Settings holds the
explanation for as long as the user needs it.

## Consequences

- A hung model request is abandoned, not awaited: its answer may arrive
  after the session ended and is dropped.
- Guardrail refusals insert the raw words, so profanity the model
  declines to touch still lands in the target app.
- The 4096-token context bounds a session, so very long dictations may
  fail shaping and pass through unshaped.
- This ADR ships fork-first and is offered upstream as a draft.
