# A user-authored Vocabulary biases recognition

Direct Dictation gains a **Vocabulary**: words the user types in Settings that
Apple Speech is told to expect. The terms reach the recognizer through
`AnalysisContext.contextualStrings`, applied with `SpeechAnalyzer.setContext`
when an analyzer is prepared.

This closes the one accuracy gap a general on-device model cannot close by
itself. The model has never heard the user's colleague, product or codebase, so
it mishears them every session, and no better model fixes it because the
information is not in the model.

Biasing before the words are heard, rather than rewriting text after. A
find-and-replace pass over finished text has no edge to its category: a list
holding "mm" turns "the gap is 3 mm" into "the gap is 3", silently, with no
undo. Biasing can only make a word Talkify was told about more likely; it never
edits what was said.

## Consequences

- Terms are applied when an analyzer is prepared, never on the keypress:
  `setContext` is async, and the warm session exists so the key meets an
  analyzer with nothing left to do.
- Editing the list drops the warm analyzers so the next prewarm rebuilds with
  the new terms. Pushing terms into a live analyzer would leave a session that
  is already recording biased two ways.
- Failing to bias never fails a session. It is a hint, and an analyzer that
  refused it transcribes exactly as an empty list does.
- Nothing is derived from what was dictated. The list holds what the user typed
  and nothing else, so "Talkify persists no recognized text" is untouched.
- One list across both dictation languages. A name is spelled the same way
  whichever language surrounds it.
- At most 100 terms, which is Apple's documented ceiling across all tags, and
  64 characters each, which is a guard rather than a limit.
- Stored in `AppSettings` on UserDefaults with every other preference, and
  sanitized on read: an older build may have written more, longer, or duplicate
  terms.

The mechanism was found by @kalki-kgp in issue #19, along with Apple's phrase
ceiling.
