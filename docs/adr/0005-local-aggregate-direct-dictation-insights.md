# Local aggregate Direct Dictation Insights

Talkify stores daily aggregate usage for completed Direct Dictation sessions. Each daily record contains a calendar day, word count, speaking duration, and session count. Insights derives totals, weighted words per minute, average words per session, a 14-day chart, rolling seven-day Voice Momentum, streaks, and a 16-week heatmap from those records.

The usage store never receives recognized text or target application identifiers. Talkify writes the JSON document to its Application Support directory. The feature has no account, network service, or cross-device sync.

## Consequences

- A session counts only after Talkify inserts nonempty recognized text.
- Cancelled, failed, and silent sessions do not change usage.
- Word count is computed in memory before the aggregate reaches persistence.
- Average words per minute uses total words divided by total speaking minutes.
- Voice Momentum compares the last seven days with the previous seven days.
- Current streak includes activity today or yesterday. It becomes zero after a full inactive day.
- Insights appears below Sounds in Settings. It has no separate window or menu-bar entry.
- Voice analysis, automatic-fix counts, percentiles, application breakdowns, and leaderboards require different data and remain out of scope.
