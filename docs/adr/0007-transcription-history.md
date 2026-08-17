# Transcription history

Direct Dictation gains an off-by-default transcription history: while the
setting is on, each completed session appends one timestamped entry to a
daily plain-text file. The default folder is `~/Documents/Talkify/`,
user-visible on purpose, unlike the Application Support JSON Insights keeps
for data only Talkify reads. The write happens before the insertion outcome
is routed, so a failed paste cannot lose the words that were spoken.

Daily plain text was chosen over JSONL and over one file per session. The
folder exists for the user to read in Finder: a day of dictation reads as
one document, a folder of per-session fragments does not, and plain text
means no viewer needs building. JSONL stays available later if a history
browser UI ever exists.

The privacy tradeoff is stated plainly: this is the first feature that
persists recognized text. It reverses the standing no-persistence stance
only by explicit user choice, everything stays local, and Clear History
plus deleting the folder fully undo it.

## Consequences

- History writes are `try?` and never block or fail a session; a full disk
  loses the entry, not the dictation.
- Clear History deletes only `YYYY-MM-DD.txt`-shaped names, so a
  user-picked folder full of their own files is safe.
- The day file uses the local calendar, so a timezone change starts a new
  file mid-flight.
