# User-authored Vocabulary biases recognition

Talkify lets the user write a Vocabulary: a list of Vocabulary Terms — names, acronyms, jargon — that Apple Speech is biased toward. Talkify hands the list to each prepared `SpeechAnalyzer` as `AnalysisContext.contextualStrings` under the `.general` tag, through `SpeechAnalyzer.setContext`.

The list is authored by the user and only by the user. Talkify does not derive terms from what was dictated, does not observe what the user edits after insertion, and does not keep a record of any session in order to learn. The stored document holds the terms as typed and nothing else, which keeps the feature inside the existing rule that Talkify persists no recognized text.

Biasing is not training. No Speech Model is bundled, modified, or written to; the terms are a per-session input to an Apple-managed asset, and removing a term removes its whole effect. `SFCustomLanguageModelData` — which reaches further, into phrase-count weighting and pronunciation overrides — is available on the same stack and is deliberately not used yet.

## Consequences

- Terms are applied while a language is prewarmed, never on the Dictation Trigger press. `setContext` is async, and the warm session exists so that pressing the key meets an analyzer with nothing left to do.
- Editing the Vocabulary re-biases every warm analyzer immediately, so a term added seconds ago is live for the next session without a relaunch.
- A session already recording keeps the Vocabulary it started with, matching how Dictation session settings snapshot the rest of its preferences.
- Both Dictation Languages are biased with the same list. Terms are not scoped per language: a name is spelled the same way whichever language the sentence around it is in.
- Applying the Vocabulary can fail without ending a session. Biasing is a hint, so a failure leaves the analyzer transcribing unbiased — which is exactly the behavior of an empty Vocabulary.
- The list is capped at 100 terms, which is Apple's documented ceiling for `contextualStrings`: "Limit the total number of phrases across all tags to no more than 100." Talkify spends every phrase on the `.general` tag, so the list cap is that number.
- Terms are capped at 128 characters, which is Talkify's own guard and not a documented limit. Apple asks for phrases "relatively brief, limiting them to one or two words whenever possible" and warns that lengthy ones are less likely to be recognized — guidance rather than a ceiling. The guard exists so a pasted paragraph cannot take one of the hundred slots.
- Every mutation is one transaction inside `VocabularyStore`, which reads, applies the rule, and writes without suspending. Deriving a new list in the caller and awaiting the write would let two edits in flight read the same snapshot and overwrite each other.
- The store canonicalizes what it decodes rather than trusting the file. An older build or a hand-edited document can hold entries this build rejects, and folded duplicates in particular would give the section repeated `ForEach` identifiers and make removing either one take both.
- Mutations carry an in-memory revision, never written to the file, so a caller resuming out of order drops a stale answer instead of assigning an older list over a newer one.
- Terms are compared case-insensitively, so "Talkify" and "talkify" are one entry. They are compared with diacritics intact, because telling "resume" from "résumé" is the reason someone adds the accented spelling.
- Terms are stored as a struct rather than a bare string, so pronunciation and weighting can join the document later without a migration.
- The insertion path is untouched. This decision is independent of the insertion latency benchmark and adds nothing to what that measures.
- Learning terms automatically, per-application scoping, and cleanup of the transcribed text need a durable record of what was said and remain out of scope.
