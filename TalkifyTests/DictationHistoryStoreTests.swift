import Foundation
import Testing
@testable import Talkify

struct DictationHistoryStoreTests {
  @Test func recordCreatesFolderAndDayFileWithTimestampedEntry() async throws {
    let folder = temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let calendar = testCalendar()
    let date = try #require(calendar.date(from: DateComponents(
      year: 2026, month: 8, day: 17, hour: 14, minute: 3, second: 5
    )))
    let store = DictationHistoryStore(calendar: calendar)

    try await store.record("Hello there", at: date, in: folder)

    let fileName = DictationHistoryStore.fileName(for: date, calendar: calendar)
    let timestamp = DictationHistoryStore.timestamp(for: date, calendar: calendar)
    #expect(fileName == "2026-08-17.txt")
    #expect(timestamp == "[14:03:05]")
    let contents = try String(
      contentsOf: folder.appending(path: fileName),
      encoding: .utf8
    )
    #expect(contents == "[14:03:05]\nHello there\n\n")
  }

  @Test func sameDayRecordingsAppendInOrderToOneFile() async throws {
    let folder = temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let calendar = testCalendar()
    let first = try #require(calendar.date(from: DateComponents(
      year: 2026, month: 8, day: 17, hour: 9, minute: 0, second: 0
    )))
    let second = try #require(calendar.date(
      byAdding: .minute, value: 90, to: first
    ))
    let store = DictationHistoryStore(calendar: calendar)

    try await store.record("First entry", at: first, in: folder)
    try await store.record("Second entry", at: second, in: folder)

    let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
    #expect(files == ["2026-08-17.txt"])
    let contents = try String(
      contentsOf: folder.appending(path: "2026-08-17.txt"),
      encoding: .utf8
    )
    #expect(contents == "[09:00:00]\nFirst entry\n\n[10:30:00]\nSecond entry\n\n")
  }

  @Test func differentDaysLandInDifferentFiles() async throws {
    let folder = temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let calendar = testCalendar()
    let first = try #require(calendar.date(from: DateComponents(
      year: 2026, month: 8, day: 17, hour: 23
    )))
    let second = try #require(calendar.date(
      byAdding: .hour, value: 2, to: first
    ))
    let store = DictationHistoryStore(calendar: calendar)

    try await store.record("Late tonight", at: first, in: folder)
    try await store.record("Early tomorrow", at: second, in: folder)

    let files = try FileManager.default
      .contentsOfDirectory(atPath: folder.path)
      .sorted()
    #expect(files == ["2026-08-17.txt", "2026-08-18.txt"])
  }

  @Test func emptyAndWhitespaceOnlyTextWritesNothing() async throws {
    let folder = temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let calendar = testCalendar()
    let date = try #require(calendar.date(from: DateComponents(
      year: 2026, month: 8, day: 17, hour: 12
    )))
    let store = DictationHistoryStore(calendar: calendar)

    try await store.record("", at: date, in: folder)
    try await store.record("  \n\t ", at: date, in: folder)

    #expect(!FileManager.default.fileExists(atPath: folder.path))
    let dayFile = folder.appending(path: "2026-08-17.txt")
    #expect(!FileManager.default.fileExists(atPath: dayFile.path))
  }

  @Test func textIsTrimmedBeforeWriting() async throws {
    let folder = temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let calendar = testCalendar()
    let date = try #require(calendar.date(from: DateComponents(
      year: 2026, month: 8, day: 17, hour: 8, minute: 30, second: 15
    )))
    let store = DictationHistoryStore(calendar: calendar)

    try await store.record("  padded text \n", at: date, in: folder)

    let contents = try String(
      contentsOf: folder.appending(path: "2026-08-17.txt"),
      encoding: .utf8
    )
    #expect(contents == "[08:30:15]\npadded text\n\n")
  }

  @Test func clearRemovesOnlyDayFiles() async throws {
    let folder = temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let calendar = testCalendar()
    let date = try #require(calendar.date(from: DateComponents(
      year: 2026, month: 8, day: 17, hour: 12
    )))
    let store = DictationHistoryStore(calendar: calendar)
    try await store.record("A day of dictation", at: date, in: folder)
    let foreignNames = ["notes.txt", "2026-08-17.md", "2026-8-17.txt"]
    for name in foreignNames {
      try Data("keep me".utf8).write(to: folder.appending(path: name))
    }
    let subfolder = folder.appending(path: "keep", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(
      at: subfolder,
      withIntermediateDirectories: true
    )

    try await store.clear(folder: folder)

    let remaining = try FileManager.default
      .contentsOfDirectory(atPath: folder.path)
      .sorted()
    #expect(remaining == ["2026-08-17.md", "2026-8-17.txt", "keep", "notes.txt"])
  }

  @Test func historyFileNameMatchesOnlyTheDayFileShape() {
    #expect(DictationHistoryStore.isHistoryFileName("2026-08-17.txt"))
    #expect(!DictationHistoryStore.isHistoryFileName("notes.txt"))
    #expect(!DictationHistoryStore.isHistoryFileName("2026-08-17.md"))
    #expect(!DictationHistoryStore.isHistoryFileName("2026-8-17.txt"))
    #expect(!DictationHistoryStore.isHistoryFileName("20260817.txt"))
    #expect(!DictationHistoryStore.isHistoryFileName("2026-08-17.txt.bak"))
    #expect(!DictationHistoryStore.isHistoryFileName("aaaa-bb-cc.txt"))
  }

  @Test func defaultFolderIsTalkifyInDocuments() {
    #expect(
      DictationHistoryStore.defaultFolderURL.path
        .hasSuffix("Documents/Talkify")
    )
  }

  /// A fresh per-test folder under the system temporary directory.
  /// The point of naming the source: a day file that says only what you said
  /// is harder to use later than one that says where you were saying it.
  @Test func anEntryNamesTheApplicationItWasAimedAt() async throws {
    let folder = temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = DictationHistoryStore(calendar: testCalendar())
    let noon = Date(timeIntervalSince1970: 1_755_000_000)

    try await store.record("hello there", from: "Ghostty", at: noon, in: folder)

    let file = folder.appending(path: DictationHistoryStore.fileName(
      for: noon,
      calendar: testCalendar()
    ))
    let contents = try String(contentsOf: file, encoding: .utf8)
    let heading = DictationHistoryStore.timestamp(for: noon, calendar: testCalendar())
    #expect(contents.hasPrefix("\(heading) Ghostty\n"))
    #expect(contents.contains("hello there"))
  }

  /// An unnamed source leaves the heading exactly as it was before sources
  /// existed, so entries written by an older build still read the same.
  @Test func anUnnamedSourceLeavesTheBareTimestamp() {
    let noon = Date(timeIntervalSince1970: 1_755_000_000)
    let calendar = testCalendar()
    let bare = DictationHistoryStore.timestamp(for: noon, calendar: calendar)

    #expect(DictationHistoryStore.heading(for: noon, source: nil, calendar: calendar) == bare)
    #expect(DictationHistoryStore.heading(for: noon, source: "", calendar: calendar) == bare)
    #expect(DictationHistoryStore.heading(for: noon, source: "   ", calendar: calendar) == bare)
  }

  /// An application name is not something Talkify chose, so a name carrying a
  /// newline must not be able to forge a second entry inside this one.
  @Test func aSourceCannotForgeASecondEntry() {
    let noon = Date(timeIntervalSince1970: 1_755_000_000)
    let calendar = testCalendar()

    let heading = DictationHistoryStore.heading(
      for: noon,
      source: "Evil\n[00:00:00] injected",
      calendar: calendar
    )

    #expect(!heading.contains("\n"))
    #expect(heading.hasSuffix("Evil [00:00:00] injected"))
  }

  private func temporaryFolder() -> URL {
    FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
  }

  /// Gregorian and pinned to GMT, so file names and timestamps are fixed.
  private func testCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "GMT")!
    return calendar
  }
}
