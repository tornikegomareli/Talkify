import Foundation
import NaturalLanguage

struct UsageDay: Codable, Comparable, Hashable, Identifiable, Sendable {
  let year: Int
  let month: Int
  let day: Int

  var id: String {
    String(format: "%04d-%02d-%02d", year, month, day)
  }

  init(date: Date, calendar: Calendar) {
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    year = components.year ?? 0
    month = components.month ?? 0
    day = components.day ?? 0
  }

  func date(in calendar: Calendar) -> Date? {
    calendar.date(from: DateComponents(year: year, month: month, day: day))
  }

  func weekday(in calendar: Calendar) -> Int? {
    date(in: calendar).map { calendar.component(.weekday, from: $0) }
  }

  static func < (lhs: UsageDay, rhs: UsageDay) -> Bool {
    (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
  }
}

struct DailyUsage: Codable, Equatable, Identifiable, Sendable {
  var day: UsageDay
  var wordCount: Int
  var speakingDuration: TimeInterval
  var sessionCount: Int

  var id: UsageDay { day }
}

struct UsageDocument: Codable, Equatable, Sendable {
  static let currentVersion = 1

  var version: Int
  var days: [DailyUsage]

  init(version: Int = currentVersion, days: [DailyUsage] = []) {
    self.version = version
    self.days = days
  }
}

struct UsageSummary: Equatable, Sendable {
  let totalWords: Int
  let completedSessions: Int
  let totalSpeakingDuration: TimeInterval
  let averageWordsPerMinute: Double
  let averageWordsPerSession: Double
  let currentStreak: Int
  let longestStreak: Int
}

struct UsageTimelineDay: Equatable, Identifiable, Sendable {
  let day: UsageDay
  let date: Date
  let wordCount: Int
  let sessionCount: Int

  var id: UsageDay { day }
}

struct UsageMomentum: Equatable, Sendable {
  let currentWordCount: Int
  let previousWordCount: Int
  let activeDayCount: Int
  let sessionCount: Int

  var wordChange: Double? {
    guard previousWordCount > 0 else { return nil }
    return Double(currentWordCount - previousWordCount) / Double(previousWordCount)
  }
}

struct UsageHeatmapDay: Equatable, Identifiable, Sendable {
  let day: UsageDay
  let wordCount: Int
  let isFuture: Bool

  var id: UsageDay { day }
}

enum UsageMetrics {
  static func localCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    return calendar
  }

  static func wordCount(in text: String) -> Int {
    let tokenizer = NLTokenizer(unit: .word)
    tokenizer.string = text

    var count = 0
    tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { _, _ in
      count += 1
      return true
    }
    return count
  }

  static func summary(
    for document: UsageDocument,
    referenceDate: Date,
    calendar: Calendar
  ) -> UsageSummary {
    let totalWords = document.days.reduce(0) { result, usage in
      result + max(usage.wordCount, 0)
    }
    let completedSessions = document.days.reduce(0) { result, usage in
      result + max(usage.sessionCount, 0)
    }
    let totalDuration = document.days.reduce(0) { result, usage in
      result + max(usage.speakingDuration, 0)
    }
    let averageWordsPerMinute = totalDuration > 0
      ? Double(totalWords) / (totalDuration / 60)
      : 0
    let averageWordsPerSession = completedSessions > 0
      ? Double(totalWords) / Double(completedSessions)
      : 0
    let streaks = streaks(
      in: document.days,
      referenceDate: referenceDate,
      calendar: calendar
    )

    return UsageSummary(
      totalWords: totalWords,
      completedSessions: completedSessions,
      totalSpeakingDuration: totalDuration,
      averageWordsPerMinute: averageWordsPerMinute,
      averageWordsPerSession: averageWordsPerSession,
      currentStreak: streaks.current,
      longestStreak: streaks.longest
    )
  }

  static func timeline(
    for document: UsageDocument,
    referenceDate: Date,
    calendar: Calendar,
    dayCount: Int = 14
  ) -> [UsageTimelineDay] {
    guard dayCount > 0 else { return [] }

    let today = calendar.startOfDay(for: referenceDate)
    let totals = totalsByDay(in: document.days)

    return (0..<dayCount).compactMap { index in
      let offset = index - (dayCount - 1)
      guard let date = calendar.date(byAdding: .day, value: offset, to: today) else {
        return nil
      }
      let day = UsageDay(date: date, calendar: calendar)
      let dayTotals = totals[day, default: DayTotals()]
      return UsageTimelineDay(
        day: day,
        date: date,
        wordCount: dayTotals.wordCount,
        sessionCount: dayTotals.sessionCount
      )
    }
  }

  static func momentum(
    for document: UsageDocument,
    referenceDate: Date,
    calendar: Calendar
  ) -> UsageMomentum {
    let days = timeline(
      for: document,
      referenceDate: referenceDate,
      calendar: calendar,
      dayCount: 14
    )
    let previousDays = days.prefix(7)
    let currentDays = days.suffix(7)

    return UsageMomentum(
      currentWordCount: currentDays.reduce(0) { $0 + $1.wordCount },
      previousWordCount: previousDays.reduce(0) { $0 + $1.wordCount },
      activeDayCount: currentDays.count { $0.wordCount > 0 },
      sessionCount: currentDays.reduce(0) { $0 + $1.sessionCount }
    )
  }

  static func heatmap(
    for document: UsageDocument,
    referenceDate: Date,
    calendar: Calendar,
    weekCount: Int = 16
  ) -> [UsageHeatmapDay] {
    guard weekCount > 0 else { return [] }

    let today = calendar.startOfDay(for: referenceDate)
    guard let currentWeekStart = calendar.dateInterval(
      of: .weekOfYear,
      for: today
    )?.start,
    let firstDay = calendar.date(
      byAdding: .weekOfYear,
      value: -(weekCount - 1),
      to: currentWeekStart
    ) else {
      return []
    }

    let wordsByDay = document.days.reduce(into: [UsageDay: Int]()) { result, usage in
      result[usage.day, default: 0] += max(usage.wordCount, 0)
    }

    return (0..<(weekCount * 7)).compactMap { offset in
      guard let date = calendar.date(byAdding: .day, value: offset, to: firstDay) else {
        return nil
      }
      let day = UsageDay(date: date, calendar: calendar)
      return UsageHeatmapDay(
        day: day,
        wordCount: wordsByDay[day, default: 0],
        isFuture: calendar.compare(date, to: today, toGranularity: .day) == .orderedDescending
      )
    }
  }

  private static func streaks(
    in days: [DailyUsage],
    referenceDate: Date,
    calendar: Calendar
  ) -> (current: Int, longest: Int) {
    let activeDays = Set(days.lazy.filter {
      $0.sessionCount > 0 && $0.wordCount > 0
    }.map(\.day))
    guard !activeDays.isEmpty else { return (0, 0) }

    let sortedDays = activeDays.sorted()
    var longest = 1
    var run = 1

    for index in sortedDays.indices.dropFirst() {
      let previous = sortedDays[sortedDays.index(before: index)]
      if day(after: previous, calendar: calendar) == sortedDays[index] {
        run += 1
        longest = max(longest, run)
      } else {
        run = 1
      }
    }

    let today = UsageDay(date: referenceDate, calendar: calendar)
    let startDay: UsageDay?
    if activeDays.contains(today) {
      startDay = today
    } else if let yesterday = day(before: today, calendar: calendar),
         activeDays.contains(yesterday) {
      startDay = yesterday
    } else {
      startDay = nil
    }

    var current = 0
    var cursor = startDay
    while let day = cursor, activeDays.contains(day) {
      current += 1
      cursor = self.day(before: day, calendar: calendar)
    }

    return (current, longest)
  }

  private struct DayTotals {
    var wordCount = 0
    var sessionCount = 0
  }

  private static func totalsByDay(in days: [DailyUsage]) -> [UsageDay: DayTotals] {
    days.reduce(into: [UsageDay: DayTotals]()) { result, usage in
      result[usage.day, default: DayTotals()].wordCount += max(usage.wordCount, 0)
      result[usage.day, default: DayTotals()].sessionCount += max(usage.sessionCount, 0)
    }
  }

  private static func day(after day: UsageDay, calendar: Calendar) -> UsageDay? {
    adjustedDay(day, value: 1, calendar: calendar)
  }

  private static func day(before day: UsageDay, calendar: Calendar) -> UsageDay? {
    adjustedDay(day, value: -1, calendar: calendar)
  }

  private static func adjustedDay(
    _ day: UsageDay,
    value: Int,
    calendar: Calendar
  ) -> UsageDay? {
    guard let date = day.date(in: calendar),
       let adjustedDate = calendar.date(byAdding: .day, value: value, to: date) else {
      return nil
    }
    return UsageDay(date: adjustedDate, calendar: calendar)
  }
}
