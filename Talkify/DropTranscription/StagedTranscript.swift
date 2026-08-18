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

  /// Where staging folders live between the transcript being produced and the
  /// user deciding where it goes.
  static var defaultRoot: URL { URL.temporaryDirectory.appending(path: "Talkify") }

  /// Writes the text into a folder of its own, so the file can carry its real
  /// name without colliding with another job's.
  ///
  /// The folder is 0700 and the file 0600: a transcript is the user's speech
  /// in cleartext, and Talkify is unsandboxed, so anything else running as the
  /// same user could otherwise read it.
  static func stage(
    text: String,
    source: URL,
    root: URL = defaultRoot
  ) throws -> StagedTranscript {
    try prepareRoot(root)
    let directory = root.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    let name = source.deletingPathExtension().lastPathComponent
    let url = directory.appending(path: "\(name).txt")
    try text.write(to: url, atomically: true, encoding: .utf8)
    // After the write: `atomically` renames a temporary file into place, so
    // permissions set beforehand would belong to a file that no longer exists.
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    return StagedTranscript(url: url, source: source)
  }

  /// Clears anything left in the staging root.
  ///
  /// Cleanup otherwise only happens on `commit()` or `discard()`, so a crash
  /// or a force-quit while a card was on screen left the transcript readable
  /// under `$TMPDIR` indefinitely. Called at launch, before anything is
  /// staged, so everything it finds belongs to a run that is already over.
  static func sweep(root: URL = defaultRoot) {
    try? FileManager.default.removeItem(at: root)
  }

  /// Refuses to stage into a root that something replaced with a symlink,
  /// which would put the transcript wherever that link points.
  private static func prepareRoot(_ root: URL) throws {
    let attributes = try? FileManager.default.attributesOfItem(atPath: root.path)
    if let type = attributes?[.type] as? FileAttributeType, type == .typeSymbolicLink {
      try FileManager.default.removeItem(at: root)
    }
    try FileManager.default.createDirectory(
      at: root,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
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
