import Foundation

/// Where a finished Drop Transcription is written.
///
/// Beside its source by default, because that is the folder the user was
/// already looking at when they picked the file up. The fallbacks exist for
/// sources that cannot be written next to: a read-only volume, a mounted disk
/// image, a network share.
enum TranscriptDestination {
  /// The Settings pick. Its rawValue is stored in UserDefaults, so renaming a
  /// case silently resets the preference.
  enum Preference: String, CaseIterable {
    case besideSource = "Beside the file"
    case chosenFolder = "Chosen folder"
  }

  /// The filesystem questions this needs answered, injected so the resolution
  /// rules can be tested without touching a disk.
  struct Probe: Sendable {
    var isDirectoryWritable: @Sendable (URL) -> Bool
    var fileExists: @Sendable (URL) -> Bool

    static let live = Probe(
      isDirectoryWritable: { FileManager.default.isWritableFile(atPath: $0.path(percentEncoded: false)) },
      fileExists: { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
    )
  }

  /// The first writable directory in the preference's fallback chain. Desktop
  /// is the last resort because it is the one folder every Mac has and the
  /// user will certainly find.
  static func directory(
    for source: URL,
    preference: Preference,
    chosenFolder: URL?,
    desktop: URL,
    probe: Probe = .live
  ) -> URL {
    let candidates: [URL?] = switch preference {
    case .besideSource: [source.deletingLastPathComponent(), chosenFolder, desktop]
    case .chosenFolder: [chosenFolder, source.deletingLastPathComponent(), desktop]
    }

    for case let candidate? in candidates where probe.isDirectoryWritable(candidate) {
      return candidate
    }
    return desktop
  }

  /// `memo.txt`, or `memo-2.txt` when that name is taken. A transcript must
  /// never overwrite an earlier one: the second run of a file is usually the
  /// one the user is comparing against the first.
  static func uniqueURL(
    in directory: URL,
    basename: String,
    extension pathExtension: String = "txt",
    probe: Probe = .live
  ) -> URL {
    let candidate = directory.appending(path: "\(basename).\(pathExtension)")
    guard probe.fileExists(candidate) else { return candidate }

    var suffix = 2
    while true {
      let next = directory.appending(path: "\(basename)-\(suffix).\(pathExtension)")
      if !probe.fileExists(next) { return next }
      suffix += 1
    }
  }

  static func resolve(
    for source: URL,
    preference: Preference,
    chosenFolder: URL?,
    desktop: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Desktop"),
    probe: Probe = .live
  ) -> URL {
    let directory = directory(
      for: source,
      preference: preference,
      chosenFolder: chosenFolder,
      desktop: desktop,
      probe: probe
    )
    return uniqueURL(
      in: directory,
      basename: source.deletingPathExtension().lastPathComponent,
      probe: probe
    )
  }
}
