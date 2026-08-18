# Three-way insertion destination

Direct Dictation gains an insertion destination setting with three
deliveries: insert into the app (paste, then restore the previous
clipboard), copy to the clipboard (never paste), and insert and copy
(paste and leave the text on the clipboard). Inserting stays the default,
so nothing changes for anyone who never opens the setting. The choice is
plumbed through the immutable session settings snapshot (ADR-0004) and
delivered by `TextInsertionService`: clipboard-only returns before focus
validation, since there is no target to validate, and insert-and-copy
skips both the clipboard snapshot acquisition and the restore.

Two kinds of users asked for this. Some prefer owning the paste: they
want dictated text staged where they can place it deliberately rather
than landing wherever focus sat. Others run clipboard-history managers
and were losing every dictation to the restore step, which put the old
clipboard back over the text they had just spoken.

## Consequences

- Clipboard-only reports `.copiedToClipboard`, which still plays the
  paste sound and records usage; delivery to the clipboard is a
  completed session, not a fallback.
- Insert-and-copy deliberately leaves the clipboard dirty; that is the
  point, not a bug to fix.
- The Settings window gains its first behavior section, named Dictation,
  alongside the existing look-and-feel sections.
