import Foundation

/// Writes finished Direct Dictation text into a folder of daily plain-text
/// files, one timestamped entry per completed session.
///
/// The store only runs while the off-by-default history setting is on:
/// persisting no recognized text is the project's standing privacy stance,
/// and turning this on is the user's explicit choice to trade some of it for
/// a record. The folder is user-visible on purpose — history the user asked
/// for belongs where the user can read, search, and delete it in Finder.
actor DictationHistoryStore {
  /// `~/Documents/Talkify/`: user-visible and user-related, unlike the
  /// Application Support folder Insights uses for data only Talkify reads.
  static var defaultFolderURL: URL {
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
      .appending(path: "Talkify", directoryHint: .isDirectory)
  }

  /// One file per local calendar day, so a day of dictation reads as one
  /// document instead of a folder of fragments.
  static func fileName(for date: Date, calendar: Calendar = .current) -> String {
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    return String(
      format: "%04d-%02d-%02d.txt",
      parts.year ?? 0, parts.month ?? 0, parts.day ?? 0
    )
  }

  /// The entry's leading timestamp line, in the day's own clock time.
  static func timestamp(for date: Date, calendar: Calendar = .current) -> String {
    let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
    return String(
      format: "[%02d:%02d:%02d]",
      parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0
    )
  }

  /// The entry's heading: the time, and where the text was going.
  ///
  /// The source is where the words were aimed, which is the application that
  /// held focus when the session started. History is written before insertion
  /// so a failed paste cannot lose the text, so where it landed is not known
  /// yet. An unnamed source leaves the heading as the bare timestamp rather
  /// than writing "Unknown".
  static func heading(
    for date: Date,
    source: String?,
    calendar: Calendar = .current
  ) -> String {
    let time = timestamp(for: date, calendar: calendar)
    guard let source, !source.trimmingCharacters(in: .whitespaces).isEmpty else {
      return time
    }
    // Newlines would forge a second entry inside this one.
    let clean = source
      .replacingOccurrences(of: "\n", with: " ")
      .replacingOccurrences(of: "\r", with: " ")
      .trimmingCharacters(in: .whitespaces)
    return "\(time) \(clean)"
  }

  private let calendar: Calendar

  init(calendar: Calendar = .current) {
    self.calendar = calendar
  }

  /// Appends one session's text to its day file, creating the folder and the
  /// file as needed. Nothing is ever overwritten: a day file only grows.
  func record(
    _ text: String,
    from source: String? = nil,
    at date: Date = .now,
    in folder: URL
  ) throws {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }

    try FileManager.default.createDirectory(
      at: folder,
      withIntermediateDirectories: true
    )

    let fileURL = folder.appending(path: Self.fileName(for: date, calendar: calendar))
    let heading = Self.heading(for: date, source: source, calendar: calendar)
    let entry = "\(heading)\n\(trimmed)\n\n"
    let entryData = Data(entry.utf8)

    if let handle = try? FileHandle(forWritingTo: fileURL) {
      defer { try? handle.close() }
      try handle.seekToEnd()
      try handle.write(contentsOf: entryData)
    } else {
      try entryData.write(to: fileURL, options: .withoutOverwriting)
    }
  }

  /// Deletes only the day files this store wrote. The folder is the user's —
  /// they may have picked one holding their own files, and Clear History
  /// must never take anything Talkify did not put there.
  func clear(folder: URL) throws {
    let contents = try FileManager.default.contentsOfDirectory(
      at: folder,
      includingPropertiesForKeys: nil
    )
    for file in contents where Self.isHistoryFileName(file.lastPathComponent) {
      try FileManager.default.removeItem(at: file)
    }
  }

  /// `2026-08-17.txt` and nothing else.
  static func isHistoryFileName(_ name: String) -> Bool {
    guard name.count == 14, name.hasSuffix(".txt") else { return false }
    let stem = name.dropLast(4)
    for (offset, character) in stem.enumerated() {
      if offset == 4 || offset == 7 {
        guard character == "-" else { return false }
      } else {
        guard character.isASCII, character.isNumber else { return false }
      }
    }
    return true
  }
}
