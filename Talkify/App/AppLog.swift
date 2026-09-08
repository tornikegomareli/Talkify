import os

/// Where the app says what it is doing.
///
/// It exists because it did not. When dictation stopped hearing anything on
/// Bluetooth, `AVAudioEngine` had stopped itself and said so to nobody: the
/// system log held not one line from this process, and finding it took four
/// throwaway binaries reproducing the audio stack outside the app (#129).
///
/// **Nothing that carries what the user said goes through here.** No
/// transcripts, no drafts, no clipboard contents, no prompt text, no dropped
/// file names. CONTEXT.md promises no history beyond the local usage metrics,
/// and a log holding dictated words breaks that promise whatever the level it
/// is written at, because `log show` reads them all.
///
/// `Logger` redacts interpolated values unless they are marked public, which
/// makes the safe thing the default. The rule on top of it: only durations,
/// states, locale identifiers, counts and error descriptions are ever marked
/// public, and anything derived from what was said is left redacted or simply
/// not logged. A length is fine; the text of that length is not.
enum AppLog {
  private static let subsystem = "com.tgomareli.Talkify"

  /// Sessions beginning and ending, and how they ended.
  static let session = Logger(subsystem: subsystem, category: "session")
  /// The microphone: the engine, the audio route, and the rebuilds it forces.
  static let audio = Logger(subsystem: subsystem, category: "audio")
  /// Recognition: preparing a model, downloading one, finishing a transcript.
  static let speech = Logger(subsystem: subsystem, category: "speech")
  /// What becomes of finished text: shaping, translation, insertion.
  static let delivery = Logger(subsystem: subsystem, category: "delivery")
}
