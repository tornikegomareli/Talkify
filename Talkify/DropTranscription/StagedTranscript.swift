import Foundation

/// A finished transcript held in a temporary folder while the HUD offers it.
///
/// A Drop Transcription is not written where it will live the moment it is
/// produced. It is staged first, under the name it will keep, and what the user
/// does next decides where it lands: dragging the card out is the save, and
/// letting the card expire commits it to the Save-to location.
///
/// Staging rather than holding the text in memory means the file is real for
/// the whole of the card's life. A drag needs something on disk to carry, and
/// a quit or a second dropped file can still write the transcript out.
struct StagedTranscript {
  /// The staged file, already named as it will be wherever it ends up.
  let url: URL
  /// The media file this came from. The Save-to location is resolved from it.
  let source: URL

  private var stagingDirectory: URL { url.deletingLastPathComponent() }

  /// Writes the text into a folder of its own, so the file can carry its real
  /// name without colliding with another job's.
  static func stage(
    text: String,
    source: URL,
    root: URL = URL.temporaryDirectory.appending(path: "Talkify")
  ) throws -> StagedTranscript {
    let directory = root.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let name = source.deletingPathExtension().lastPathComponent
    let url = directory.appending(path: "\(name).txt")
    try text.write(to: url, atomically: true, encoding: .utf8)
    return StagedTranscript(url: url, source: source)
  }

  /// Moves the staged file to where the Save-to preference says it belongs,
  /// and answers with where it landed.
  @discardableResult
  func commit(
    preference: TranscriptDestination.Preference,
    chosenFolder: URL?
  ) throws -> URL {
    let destination = TranscriptDestination.resolve(
      for: source,
      preference: preference,
      chosenFolder: chosenFolder
    )
    try FileManager.default.moveItem(at: url, to: destination)
    discard()
    return destination
  }

  /// Removes the staging folder. Safe once a drag has already taken the file
  /// out of it, and safe to call twice.
  func discard() {
    try? FileManager.default.removeItem(at: stagingDirectory)
  }
}
