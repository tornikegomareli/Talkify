import Foundation
import Testing
@testable import Talkify

struct UsageStoreTests {
  @Test func mergesSameDaySessionsAndPersistsOnlyAggregates() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appending(
        path: "TalkifyUsageStoreTests-" + UUID().uuidString,
        directoryHint: .isDirectory
      )
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appending(path: "usage.json")
    let calendar = testCalendar()
    let date = try #require(calendar.date(from: DateComponents(
      year: 2026,
      month: 8,
      day: 9,
      hour: 12
    )))
    let store = UsageStore(fileURL: fileURL)

    _ = try await store.recordSession(
      wordCount: 40,
      speakingDuration: 20,
      at: date,
      calendar: calendar
    )
    _ = try await store.recordSession(
      wordCount: 80,
      speakingDuration: 30,
      at: date,
      calendar: calendar
    )

    let reloaded = UsageStore(fileURL: fileURL)
    let document = try await reloaded.load()
    let day = try #require(document.days.first)
    #expect(document.days.count == 1)
    #expect(day.wordCount == 120)
    #expect(day.speakingDuration == 50)
    #expect(day.sessionCount == 2)

    let storedData = try Data(contentsOf: fileURL)
    let json = try #require(
      JSONSerialization.jsonObject(with: storedData) as? [String: Any]
    )
    let storedDays = try #require(json["days"] as? [[String: Any]])
    let storedDay = try #require(storedDays.first)
    #expect(Set(json.keys) == ["days", "version"])
    #expect(Set(storedDay.keys) == [
      "day",
      "sessionCount",
      "speakingDuration",
      "wordCount",
    ])
  }

  @Test func storesSessionsOnTheirLocalCalendarDay() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appending(
        path: "TalkifyUsageStoreTests-" + UUID().uuidString,
        directoryHint: .isDirectory
      )
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appending(path: "usage.json")
    let calendar = testCalendar()
    let firstDate = try #require(calendar.date(from: DateComponents(
      year: 2026,
      month: 8,
      day: 9,
      hour: 23
    )))
    let secondDate = try #require(calendar.date(
      byAdding: .hour,
      value: 2,
      to: firstDate
    ))
    let store = UsageStore(fileURL: fileURL)

    _ = try await store.recordSession(
      wordCount: 20,
      speakingDuration: 10,
      at: firstDate,
      calendar: calendar
    )
    let document = try await store.recordSession(
      wordCount: 30,
      speakingDuration: 12,
      at: secondDate,
      calendar: calendar
    )

    #expect(document.days.count == 2)
    #expect(document.days.map(\.wordCount) == [20, 30])
  }

  private func testCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    calendar.firstWeekday = 2
    return calendar
  }
}
