import Foundation
import Observation

@MainActor
@Observable
final class UsageTracker {
    private let store: UsageStore

    private(set) var document = UsageDocument()
    private(set) var errorMessage: String?

    init(store: UsageStore = UsageStore()) {
        self.store = store
    }

    func load() async {
        do {
            document = try await store.load()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func recordSession(
        wordCount: Int,
        speakingDuration: TimeInterval,
        at date: Date = .now,
        calendar: Calendar = UsageMetrics.localCalendar()
    ) async {
        guard wordCount > 0 else { return }

        do {
            document = try await store.recordSession(
                wordCount: wordCount,
                speakingDuration: speakingDuration,
                at: date,
                calendar: calendar
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func summary(
        referenceDate: Date = .now,
        calendar: Calendar = UsageMetrics.localCalendar()
    ) -> UsageSummary {
        UsageMetrics.summary(
            for: document,
            referenceDate: referenceDate,
            calendar: calendar
        )
    }

    func heatmap(
        referenceDate: Date = .now,
        calendar: Calendar = UsageMetrics.localCalendar()
    ) -> [UsageHeatmapDay] {
        UsageMetrics.heatmap(
            for: document,
            referenceDate: referenceDate,
            calendar: calendar
        )
    }

    func timeline(
        referenceDate: Date = .now,
        calendar: Calendar = UsageMetrics.localCalendar(),
        dayCount: Int = 14
    ) -> [UsageTimelineDay] {
        UsageMetrics.timeline(
            for: document,
            referenceDate: referenceDate,
            calendar: calendar,
            dayCount: dayCount
        )
    }

    func momentum(
        referenceDate: Date = .now,
        calendar: Calendar = UsageMetrics.localCalendar()
    ) -> UsageMomentum {
        UsageMetrics.momentum(
            for: document,
            referenceDate: referenceDate,
            calendar: calendar
        )
    }
}
