# User-authored spelling replacements

Direct Dictation gains a **Spelling replacement** list: whole-word from→to
pairs the user types in Settings. After recognition, and before Prompt
Shaping or translation, each pair is applied to the live draft and to the
text that will be inserted. Drop Transcription uses the same list on a
finished file job.

This is the feature #19 tried to ship as recognition biasing. Apple's
`AnalysisContext.contextualStrings` are on the macOS 26 stack, but
`SpeechTranscriber` does not take them into account — measured in that
issue, and confirmed by Apple. A list of terms handed to the analyzer
does not change "Hetty" into "Hedy". The only thing that does, today, is
rewriting the text after the Speech Model has produced it.

#19 closed find-and-replace because a substring swap has no edge: a list
holding "mm" would eat it inside "comment". Whole-word matching is that
edge. A match has to start where a word starts and end where one ends,
counting letters, digits and the apostrophe as word characters. It does
not stop a user who adds the word "mm" from rewriting "3 mm"; that is the
pair they typed. It does stop a pair from rewriting a longer token that
only contains the letters.

The edge is the boundary, not the token, so the left side may hold spaces
or hyphens. That matters more than it sounds: the recognizer's usual
failure on a name is to split it, and a rule that only ever matched one
token would have no answer for "ex code" or "e-mail" — the forms the user
actually has to correct. A boundary rule covers both without a second
mechanism.

Every pair is measured against what was said, in one left-to-right pass,
and the longest matching left side wins. Feeding each pair the previous
one's output would let "colour→color" and a later "color→Color" turn
every "colour" into "Color", and the Settings list has no reordering for
the user to fix it with. Longest-match is what keeps a pair for "git"
from turning "git hub" into "Git hub".

Case-insensitive on the misspelling, trimmed on both sides, possessive
suffix preserved, because English uses that form for a name and the
recognizer misspells it the same way; the 's is left in place and rides
the new spelling. An incomplete pair is skipped, so a row being typed
cannot delete a word or send an empty transcript to Prompt Shaping.

The list is snapshotted with the rest of Dictation session settings
(ADR-0004). An empty list is the previous behavior. History keeps the
words as recognized, so a replacement is visible as a difference between
the history file and what was inserted, the same way shaping is.

This argues with CONTEXT.md's "no autocorrect" rule the same way Prompt
Shaping does: the default session is unchanged, and the rewrite is only
the pair the user wrote.

## Consequences

- This is a spelling fix, not a Speech Model. It swaps what the
  recognizer produced for what the user wrote, and only where the user
  wrote the pair; it cannot generalize to a mangling they have not seen
  yet.
- A failed translation rescues the replaced spelling, not the recognized
  one. Shaping is dropped there because it is a convenience; a
  replacement is not.
- Custom pronunciations (`SFCustomLanguageModelData`) stay out of scope.
  They need X-SAMPA and attach to `DictationTranscriber`, which Talkify
  does not use.
