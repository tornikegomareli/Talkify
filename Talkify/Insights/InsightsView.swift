import Charts
import Foundation
import SwiftUI

/// The Insights section, in the WhoopScope trends language: summary cards
/// with a comparison sentence against the previous period, then full-width
/// chart surfaces whose subtitle doubles as the scrubbed readout — the
/// selection value lives in the card header, never in a floating tooltip.
struct InsightsSettings: View {
    let tracker: UsageTracker

    private var summary: UsageSummary {
        tracker.summary()
    }

    private var timeline: [UsageTimelineDay] {
        tracker.timeline()
    }

    private var momentum: UsageMomentum {
        tracker.momentum()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let errorMessage = tracker.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Insights data error: \(errorMessage)")
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 180), spacing: 12)],
                alignment: .leading,
                spacing: 12
            ) {
                InsightSummaryCard.wordsThisWeek(momentum)
                InsightSummaryCard.averagePace(summary)
                InsightSummaryCard.voiceTime(summary)
            }

            if summary.completedSessions == 0 {
                ContentUnavailableView(
                    "No dictation data yet",
                    systemImage: "chart.xyaxis.line",
                    description: Text(
                        "Insights appear after your first completed Direct Dictation session."
                    )
                )
                .insightsCard()
            } else {
                WordsTrendChart(days: timeline)
                SessionsTrendChart(days: timeline)
                ActivityHeatmapCard(summary: summary, days: tracker.heatmap())
            }
        }
        .task {
            await tracker.load()
        }
    }
}

// MARK: - Palette

/// Per-metric tints, one hue per metric across the whole section.
private enum InsightsPalette {
    static let words = SettingsTheme.accent
    static let sessions = Color(red: 0.20, green: 0.82, blue: 0.58)
    static let time = Color(red: 0.62, green: 0.50, blue: 0.98)
}

// MARK: - Summary cards

private struct InsightSummaryCard: View {
    let title: String
    let symbol: String
    let value: String
    let unit: String
    let comparison: String
    let caption: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundStyle(tint)

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                if !unit.isEmpty {
                    Text(unit)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Text(comparison)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)

            Text(caption)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .insightsCard()
        .accessibilityElement(children: .combine)
    }

    static func wordsThisWeek(_ momentum: UsageMomentum) -> Self {
        let comparison: String
        if momentum.previousWordCount == 0 {
            comparison = "Previous week unavailable"
        } else if let change = momentum.wordChange {
            let percentage = Int((abs(change) * 100).rounded())
            comparison = percentage < 5
                ? "About the same as the previous week"
                : "\(percentage)% \(change > 0 ? "higher" : "lower") than the previous week"
        } else {
            comparison = "Previous week unavailable"
        }
        return Self(
            title: "Words this week",
            symbol: "text.word.spacing",
            value: momentum.currentWordCount.formatted(),
            unit: "",
            comparison: comparison,
            caption: "Based on \(InsightsFormat.count(momentum.sessionCount, singular: "session"))",
            tint: InsightsPalette.words
        )
    }

    static func averagePace(_ summary: UsageSummary) -> Self {
        Self(
            title: "Average pace",
            symbol: "speedometer",
            value: Int(summary.averageWordsPerMinute.rounded()).formatted(),
            unit: "wpm",
            comparison: "Weighted by active speaking time",
            caption: "Across \(InsightsFormat.count(summary.completedSessions, singular: "scored session"))",
            tint: InsightsPalette.sessions
        )
    }

    static func voiceTime(_ summary: UsageSummary) -> Self {
        Self(
            title: "Voice time",
            symbol: "waveform",
            value: InsightsFormat.durationValue(summary.totalSpeakingDuration),
            unit: InsightsFormat.durationUnit(summary.totalSpeakingDuration),
            comparison: "\(summary.totalWords.formatted()) words dictated in total",
            caption: "Longest streak · \(InsightsFormat.count(summary.longestStreak, singular: "day"))",
            tint: InsightsPalette.time
        )
    }
}

// MARK: - Chart surface

/// A chart card whose subtitle is the live readout: idle it explains the
/// chart, scrubbed it shows the selected day's values.
private struct InsightChartSurface<Content: View>: View {
    let title: String
    let symbol: String
    let tint: Color
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Label(title, systemImage: symbol)
                    .font(.headline)
                    .foregroundStyle(tint)

                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .insightsCard()
    }
}

// MARK: - Words per day

private struct WordsTrendChart: View {
    let days: [UsageTimelineDay]

    @State private var selectedDate: Date?

    private var selectedDay: UsageTimelineDay? {
        guard let selectedDate else { return nil }
        return days.min {
            abs($0.date.timeIntervalSince(selectedDate))
                < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    private var subtitle: String {
        guard let selectedDay else {
            let total = days.reduce(0) { $0 + $1.wordCount }
            return "\(total.formatted()) words dictated over the last 14 days"
        }
        let date = selectedDay.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        return "\(date) · \(selectedDay.wordCount.formatted()) words"
    }

    var body: some View {
        InsightChartSurface(
            title: "Words per day",
            symbol: "text.word.spacing",
            tint: InsightsPalette.words,
            subtitle: subtitle
        ) {
            Chart {
                ForEach(days) { day in
                    BarMark(
                        x: .value("Date", day.date, unit: .day),
                        y: .value("Words dictated", day.wordCount),
                        width: .ratio(0.62)
                    )
                    .foregroundStyle(InsightsPalette.words.gradient)
                    .clipShape(.rect(cornerRadius: 4))
                }

                if let selectedDay {
                    RuleMark(x: .value("Selected date", selectedDay.date, unit: .day))
                        .foregroundStyle(.secondary)
                        .lineStyle(.init(lineWidth: 1, dash: [4, 4]))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) {
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
            .insightsDateAxis(days)
            .chartXSelection(value: $selectedDate)
            .frame(minHeight: 200)
            .accessibilityLabel("Words dictated per day over the last fourteen days")
        }
    }
}

// MARK: - Sessions per day

private struct SessionsTrendChart: View {
    let days: [UsageTimelineDay]

    @State private var selectedDate: Date?

    private var selectedDay: UsageTimelineDay? {
        guard let selectedDate else { return nil }
        return days.min {
            abs($0.date.timeIntervalSince(selectedDate))
                < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    private var subtitle: String {
        guard let selectedDay else {
            let total = days.reduce(0) { $0 + $1.sessionCount }
            return "\(InsightsFormat.count(total, singular: "session")) in the last 14 days"
        }
        let date = selectedDay.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        return "\(date) · \(InsightsFormat.count(selectedDay.sessionCount, singular: "session"))"
    }

    var body: some View {
        InsightChartSurface(
            title: "Sessions",
            symbol: "mic.fill",
            tint: InsightsPalette.sessions,
            subtitle: subtitle
        ) {
            Chart {
                ForEach(days) { day in
                    LineMark(
                        x: .value("Date", day.date, unit: .day),
                        y: .value("Sessions", day.sessionCount)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(InsightsPalette.sessions)

                    PointMark(
                        x: .value("Date", day.date, unit: .day),
                        y: .value("Sessions", day.sessionCount)
                    )
                    .foregroundStyle(InsightsPalette.sessions)
                    .symbolSize(20)
                }

                if let selectedDay {
                    RuleMark(x: .value("Selected date", selectedDay.date, unit: .day))
                        .foregroundStyle(.secondary)
                        .lineStyle(.init(lineWidth: 1, dash: [4, 4]))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) {
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
            .insightsDateAxis(days)
            .chartXSelection(value: $selectedDate)
            .frame(minHeight: 170)
            .accessibilityLabel("Direct Dictation sessions per day over the last fourteen days")
        }
    }
}

private extension View {
    /// Pinned date domain with about seven labeled ticks, WhoopScope-style.
    func insightsDateAxis(_ days: [UsageTimelineDay]) -> some View {
        let firstDate = days.first?.date ?? .now
        let lastDate = days.last?.date ?? .now
        let domainEnd = lastDate > firstDate
            ? lastDate.addingTimeInterval(12 * 60 * 60)
            : firstDate.addingTimeInterval(24 * 60 * 60)

        return chartXScale(domain: firstDate.addingTimeInterval(-12 * 60 * 60)...domainEnd)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 7)) {
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
    }
}

// MARK: - Activity heatmap

private struct ActivityHeatmapCard: View {
    let summary: UsageSummary
    let days: [UsageHeatmapDay]

    private var subtitle: String {
        "\(InsightsFormat.count(summary.currentStreak, singular: "day")) streak · "
            + "longest \(InsightsFormat.count(summary.longestStreak, singular: "day"))"
    }

    var body: some View {
        InsightChartSurface(
            title: "Activity",
            symbol: "calendar",
            tint: InsightsPalette.words,
            subtitle: subtitle
        ) {
            ActivityHeatmapChart(days: days)
            ActivityLegend()
        }
    }
}

private struct ActivityHeatmapChart: View {
    private static let weekCount = 16

    private let chartDays: [HeatmapChartDay]
    private let monthLabels: [Int: String]
    private let monthTicks: [Double]
    private let weekdayLabels: [String]

    init(days: [UsageHeatmapDay]) {
        let calendar = UsageMetrics.localCalendar()
        let maximumWordCount = days.lazy
            .filter { !$0.isFuture }
            .map(\.wordCount)
            .max() ?? 0

        chartDays = days.enumerated().map { index, day in
            let date = day.day.date(in: calendar) ?? .distantPast
            let intensity: CGFloat
            if day.wordCount > 0, maximumWordCount > 0 {
                let ratio = Double(day.wordCount) / Double(maximumWordCount)
                intensity = 0.28 + 0.72 * ratio.squareRoot()
            } else {
                intensity = 1
            }

            return HeatmapChartDay(
                week: Double(index / 7),
                row: Double(6 - index % 7),
                state: day.isFuture ? "Future" : day.wordCount > 0 ? "Active" : "Inactive",
                intensity: intensity,
                accessibilityLabel: date.formatted(date: .complete, time: .omitted),
                accessibilityValue: "\(day.wordCount.formatted()) words dictated",
                isFuture: day.isFuture
            )
        }

        var labels: [Int: String] = [:]
        var previousMonth: Int?
        for (index, day) in days.enumerated() where index.isMultiple(of: 7) {
            guard let date = day.day.date(in: calendar) else { continue }
            let month = calendar.component(.month, from: date)
            guard month != previousMonth else { continue }
            labels[index / 7] = date.formatted(.dateTime.month(.abbreviated))
            previousMonth = month
        }
        monthLabels = labels
        monthTicks = labels.keys.sorted().map(Double.init)

        let symbols = calendar.shortWeekdaySymbols
        weekdayLabels = (0..<7).map { index in
            symbols[(calendar.firstWeekday - 1 + index) % symbols.count]
        }
    }

    var body: some View {
        Chart {
            RectanglePlot(
                chartDays,
                x: .value("Calendar Week", \.week),
                y: .value("Weekday", \.row),
                width: .ratio(0.72),
                height: .ratio(0.72)
            )
            .foregroundStyle(by: .value("Activity", \.state))
            .opacity(\.intensity)
            .accessibilityLabel(\.accessibilityLabel)
            .accessibilityValue(\.accessibilityValue)
            .accessibilityHidden(\.isFuture)
            .cornerRadius(3)
        }
        .chartForegroundStyleScale(
            domain: ["Active", "Inactive", "Future"],
            range: [
                InsightsPalette.words,
                Color.secondary.opacity(0.18),
                .clear,
            ]
        )
        .chartXScale(domain: -0.5...Double(Self.weekCount) - 0.5)
        .chartYScale(domain: -0.5...6.5)
        .chartXAxis {
            AxisMarks(position: .top, values: monthTicks) { value in
                AxisValueLabel {
                    if let tick = value.as(Double.self),
                       let label = monthLabels[Int(tick)] {
                        Text(label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: [0.0, 2.0, 4.0, 6.0]) { value in
                AxisValueLabel {
                    if let row = value.as(Double.self) {
                        Text(weekdayLabels[6 - Int(row)])
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .frame(height: 224)
        .accessibilityLabel("Sixteen-week Direct Dictation activity")
    }
}

private struct HeatmapChartDay {
    let week: Double
    let row: Double
    let state: String
    let intensity: CGFloat
    let accessibilityLabel: String
    let accessibilityValue: String
    let isFuture: Bool
}

private struct ActivityLegend: View {
    var body: some View {
        HStack(spacing: 6) {
            Text("Less")
            ForEach(1...4, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2)
                    .fill(InsightsPalette.words.opacity(0.15 + 0.2 * Double(level)))
                    .frame(width: 13, height: 13)
            }
            Text("More")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Activity ranges from less to more words dictated")
    }
}

// MARK: - Card chrome

private struct InsightsCardModifier: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .padding(18)
            .background(SettingsTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        .white.opacity(contrast == .increased ? 0.22 : 0.09),
                        lineWidth: 1
                    )
            }
    }
}

private extension View {
    func insightsCard() -> some View {
        modifier(InsightsCardModifier())
    }
}

// MARK: - Formatting

private enum InsightsFormat {
    static func durationValue(_ duration: TimeInterval) -> String {
        if duration < 60 {
            return Int(duration.rounded()).formatted()
        }
        if duration < 3_600 {
            return Int((duration / 60).rounded()).formatted()
        }
        return String(format: "%.1f", duration / 3_600)
    }

    static func durationUnit(_ duration: TimeInterval) -> String {
        if duration < 60 { return "sec" }
        if duration < 3_600 { return "min" }
        return "hr"
    }

    static func count(_ value: Int, singular: String) -> String {
        "\(value.formatted()) \(value == 1 ? singular : singular + "s")"
    }
}
