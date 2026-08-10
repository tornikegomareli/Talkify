import Foundation
import Testing
@testable import Talkify

struct UsageMetricsTests {
  @Test func countsWordsWithoutCountingPunctuationOrWhitespace() {
    #expect(UsageMetrics.wordCount(in: "  Hello, world. Talkify works!  ") == 4)
    #expect(UsageMetrics.wordCount(in: " \n\t ") == 0)
  }

  @Test func summarizesTotalsAndWeightedSpeakingSpeed() throws {
    let calendar = testCalendar()
    let firstDay = try #require(calendar.date(from: DateComponents(
      year: 2026,
      month: 8,
      day: 8
    )))
    let secondDay = try #require(calendar.date(
      byAdding: .day,
      value: 1,
      to: firstDay
    ))
    let document = UsageDocument(days: [
      DailyUsage(
        day: UsageDay(date: firstDay, calendar: calendar),
        wordCount: 300,
        speakingDuration: 120,
        sessionCount: 2
      ),
      DailyUsage(
        day: UsageDay(date: secondDay, calendar: calendar),
        wordCount: 150,
        speakingDuration: 60,
        sessionCount: 1
      ),
    ])

    let summary = UsageMetrics.summary(
      for: document,
      referenceDate: secondDay,
      calendar: calendar
    )

    #expect(summary.totalWords == 450)
    #expect(summary.completedSessions == 3)
    #expect(summary.totalSpeakingDuration == 180)
    #expect(abs(summary.averageWordsPerMinute - 150) < 0.001)
    #expect(abs(summary.averageWordsPerSession - 150) < 0.001)
  }

  @Test func calculatesCurrentAndLongestStreaks() throws {
    let calendar = testCalendar()
    let today = try #require(calendar.date(from: DateComponents(
      year: 2026,
      month: 8,
      day: 9
    )))
    let activeOffsets = [-8, -7, -6, -5, -2, -1, 0]
    let days = try activeOffsets.map { offset in
      let date = try #require(calendar.date(
        byAdding: .day,
        value: offset,
        to: today
      ))
      return DailyUsage(
        day: UsageDay(date: date, calendar: calendar),
        wordCount: 20,
        speakingDuration: 10,
        sessionCount: 1
      )
    }

    let summary = UsageMetrics.summary(
      for: UsageDocument(days: days),
      referenceDate: today,
      calendar: calendar
    )

    #expect(summary.currentStreak == 3)
    #expect(summary.longestStreak == 4)
  }

  @Test func currentStreakExpiresAfterOneInactiveDay() throws {
    let calendar = testCalendar()
    let today = try #require(calendar.date(from: DateComponents(
      year: 2026,
      month: 8,
      day: 9
    )))
    let lastActiveDate = try #require(calendar.date(
      byAdding: .day,
      value: -2,
      to: today
    ))
    let document = UsageDocument(days: [
      DailyUsage(
        day: UsageDay(date: lastActiveDate, calendar: calendar),
        wordCount: 20,
        speakingDuration: 10,
        sessionCount: 1
      ),
    ])

    let summary = UsageMetrics.summary(
      for: document,
      referenceDate: today,
      calendar: calendar
    )

    #expect(summary.currentStreak == 0)
    #expect(summary.longestStreak == 1)
  }

  @Test func heatmapContainsSixteenCalendarWeeks() throws {
    let calendar = testCalendar()
    let today = try #require(calendar.date(from: DateComponents(
      year: 2026,
      month: 8,
      day: 12
    )))
    let todayKey = UsageDay(date: today, calendar: calendar)
    let document = UsageDocument(days: [
      DailyUsage(
        day: todayKey,
        wordCount: 25,
        speakingDuration: 12,
        sessionCount: 1
      ),
    ])

    let heatmap = UsageMetrics.heatmap(
      for: document,
      referenceDate: today,
      calendar: calendar,
      weekCount: 16
    )

    #expect(heatmap.count == 112)
    #expect(heatmap.first?.day.weekday(in: calendar) == calendar.firstWeekday)
    #expect(heatmap.contains {
      $0.day == todayKey && $0.wordCount == 25 && !$0.isFuture
    })
    #expect(heatmap.filter(\.isFuture).count == 4)
  }

  @Test func timelineIncludesInactiveDaysThroughToday() throws {
    let calendar = testCalendar()
    let today = try #require(calendar.date(from: DateComponents(
      year: 2026,
      month: 8,
      day: 14
    )))
    let earlierDate = try #require(calendar.date(
      byAdding: .day,
      value: -3,
      to: today
    ))
    let document = UsageDocument(days: [
      DailyUsage(
        day: UsageDay(date: earlierDate, calendar: calendar),
        wordCount: 40,
        speakingDuration: 20,
        sessionCount: 1
      ),
      DailyUsage(
        day: UsageDay(date: today, calendar: calendar),
        wordCount: 100,
        speakingDuration: 40,
        sessionCount: 2
      ),
    ])

    let timeline = UsageMetrics.timeline(
      for: document,
      referenceDate: today,
      calendar: calendar,
      dayCount: 5
    )

    #expect(timeline.count == 5)
    #expect(timeline.map(\.wordCount) == [0, 40, 0, 0, 100])
    #expect(timeline.map(\.sessionCount) == [0, 1, 0, 0, 2])
    #expect(timeline.last?.day == UsageDay(date: today, calendar: calendar))
  }

  @Test func momentumComparesTwoRollingSevenDayPeriods() throws {
    let calendar = testCalendar()
    let today = try #require(calendar.date(from: DateComponents(
      year: 2026,
      month: 8,
      day: 14
    )))
    let samples = [
      (-9, 80),
      (-8, 20),
      (-2, 120),
      (0, 80),
    ]
    let days = try samples.map { offset, words in
      let date = try #require(calendar.date(
        byAdding: .day,
        value: offset,
        to: today
      ))
      return DailyUsage(
        day: UsageDay(date: date, calendar: calendar),
        wordCount: words,
        speakingDuration: 30,
        sessionCount: 1
      )
    }

    let momentum = UsageMetrics.momentum(
      for: UsageDocument(days: days),
      referenceDate: today,
      calendar: calendar
    )

    #expect(momentum.currentWordCount == 200)
    #expect(momentum.previousWordCount == 100)
    #expect(momentum.activeDayCount == 2)
    #expect(momentum.sessionCount == 2)
    #expect(momentum.wordChange == 1)
  }

  private func testCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    calendar.firstWeekday = 2
    return calendar
  }
}
