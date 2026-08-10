import Charts
import Foundation
import SwiftUI

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
        VStack(alignment: .leading, spacing: 18) {
            if let errorMessage = tracker.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Insights data error: \(errorMessage)")
            }

            InsightsMetricGrid(summary: summary, timeline: timeline)
            VoiceMomentumCard(momentum: momentum, summary: summary)
            DailyWordsCard(days: timeline)
            WeekdayRhythmCard(days: tracker.heatmap())
            StreakActivityCard(summary: summary, days: tracker.heatmap())
        }
        .task {
            await tracker.load()
        }
    }
}

private struct InsightsMetricGrid: View {
    let summary: UsageSummary
    let timeline: [UsageTimelineDay]

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(minimum: 150), spacing: 12),
                GridItem(.flexible(minimum: 150), spacing: 12),
                GridItem(.flexible(minimum: 150)),
            ],
            alignment: .leading,
            spacing: 12
        ) {
            InsightMetricCard(
                title: "Total Words",
                value: summary.totalWords.formatted(),
                detail: "\(summary.completedSessions.formatted()) completed sessions",
                systemImage: "text.word.spacing",
                sparkline: timeline
            )
            InsightMetricCard(
                title: "Average WPM",
                value: Int(summary.averageWordsPerMinute.rounded()).formatted(),
                detail: "Weighted by speaking time",
                systemImage: "speedometer"
            )
            InsightMetricCard(
                title: "Voice Time",
                value: InsightsFormat.duration(summary.totalSpeakingDuration),
                detail: "Active speaking time",
                systemImage: "waveform"
            )
        }
    }
}

private struct InsightMetricCard: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String
    var sparkline: [UsageTimelineDay] = []

    @Environment(\.colorSchemeContrast) private var contrast

    private var showsSparkline: Bool {
        sparkline.contains { $0.wordCount > 0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SettingsTheme.accent)
                    .frame(width: 28, height: 28)
                    .background(SettingsTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                Spacer()
                if showsSparkline {
                    MetricSparkline(days: sparkline)
                }
            }

            Text(value)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .monospacedDigit()

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(contrast == .increased ? 0.72 : 0.46))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 122, alignment: .leading)
        .insightsCard()
        .accessibilityElement(children: .combine)
    }
}

/// The 14-day trend as a minimal inline chart: no axes, no legend, just the
/// shape of the fortnight next to the headline number.
private struct MetricSparkline: View {
    let days: [UsageTimelineDay]

    var body: some View {
        Chart(days) { day in
            AreaMark(
                x: .value("Date", day.date, unit: .day),
                y: .value("Words Dictated", day.wordCount)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(
                .linearGradient(
                    colors: [SettingsTheme.accent.opacity(0.35), SettingsTheme.accent.opacity(0.02)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            LineMark(
                x: .value("Date", day.date, unit: .day),
                y: .value("Words Dictated", day.wordCount)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(SettingsTheme.accent)
            .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .frame(width: 64, height: 26)
        .accessibilityLabel("Fourteen-day words trend")
    }
}

private struct VoiceMomentumCard: View {
    let momentum: UsageMomentum
    let summary: UsageSummary

    @Environment(\.colorSchemeContrast) private var contrast

    private var headline: String {
        if momentum.currentWordCount == 0, momentum.previousWordCount == 0 {
            return "Your voice rhythm starts with the next session"
        }
        if momentum.currentWordCount == 0 {
            return "No voice activity in the last seven days"
        }
        guard let change = momentum.wordChange else {
            return "You dictated \(momentum.currentWordCount.formatted()) words in seven days"
        }

        let percentage = Int((abs(change) * 100).rounded())
        if percentage < 5 {
            return "Your voice output is steady"
        }
        return change > 0
            ? "Your voice output is up \(percentage)%"
            : "Your voice output is down \(percentage)%"
    }

    private var detail: String {
        let activeDays = InsightsFormat.count(momentum.activeDayCount, singular: "active day")
        let sessions = InsightsFormat.count(momentum.sessionCount, singular: "session")
        let average = Int(summary.averageWordsPerSession.rounded()).formatted()
        return "\(activeDays) · \(sessions) · \(average) words per session"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Label("Voice Momentum", systemImage: "waveform.path.ecg")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SettingsTheme.accent)
                    Text(headline)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(contrast == .increased ? 0.76 : 0.52))
                }
                Spacer(minLength: 12)
            }

            MomentumComparisonChart(momentum: momentum)
        }
        .insightsCard()
        .accessibilityElement(children: .contain)
    }
}

private struct MomentumComparisonChart: View {
    private let bars: [MomentumBar]

    init(momentum: UsageMomentum) {
        bars = [
            MomentumBar(period: "Previous 7 days", wordCount: momentum.previousWordCount),
            MomentumBar(period: "Last 7 days", wordCount: momentum.currentWordCount),
        ]
    }

    var body: some View {
        Chart {
            BarPlot(
                bars,
                x: .value("Words Dictated", \.wordCount),
                y: .value("Period", \.period),
                height: .ratio(0.58)
            )
            .foregroundStyle(by: .value("Period", \.period))
            .cornerRadius(5)
        }
        .chartForegroundStyleScale(
            domain: bars.map(\.period),
            range: [.white.opacity(0.24), SettingsTheme.accent]
        )
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let period = value.as(String.self) {
                        Text(period)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .frame(height: 72)
    }
}

private struct MomentumBar: Identifiable {
    let period: String
    let wordCount: Int

    var id: String { period }
}

private struct DailyWordsCard: View {
    let days: [UsageTimelineDay]

    @Environment(\.colorSchemeContrast) private var contrast
    @State private var rawSelectedDate: Date?

    private var selectedDay: UsageTimelineDay? {
        guard let rawSelectedDate else { return nil }
        return days.min {
            abs($0.date.timeIntervalSince(rawSelectedDate))
                < abs($1.date.timeIntervalSince(rawSelectedDate))
        }
    }

    private var totalWords: Int {
        days.reduce(0) { $0 + $1.wordCount }
    }

    private var yMaximum: Int {
        max(days.map(\.wordCount).max() ?? 0, 1)
    }

    /// Mean words across active days only — a fortnight of mostly-quiet days
    /// would otherwise drag the reference line into the noise floor.
    private var activeDayAverage: Int {
        let active = days.filter { $0.wordCount > 0 }
        guard !active.isEmpty else { return 0 }
        return active.reduce(0) { $0 + $1.wordCount } / active.count
    }

    private var takeaway: String {
        if let selectedDay {
            return "\(selectedDay.wordCount.formatted()) words on \(selectedDay.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))"
        }
        return "\(totalWords.formatted()) words over the last 14 days"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Speaking Activity")
                    .font(.headline)
                Text(takeaway)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(contrast == .increased ? 0.76 : 0.52))
            }

            Chart {
                ForEach(days) { day in
                    BarMark(
                        x: .value("Date", day.date, unit: .day),
                        y: .value("Words Dictated", day.wordCount),
                        width: .ratio(0.62)
                    )
                    .foregroundStyle(SettingsTheme.accent.gradient)
                    .cornerRadius(4)
                }

                if activeDayAverage > 0, selectedDay == nil {
                    RuleMark(y: .value("Daily Average", activeDayAverage))
                        .foregroundStyle(.white.opacity(0.3))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .annotation(position: .top, alignment: .trailing, spacing: 2) {
                            Text("avg \(activeDayAverage.formatted())")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.45))
                        }
                }

                if let selectedDay {
                    RuleMark(x: .value("Selected Date", selectedDay.date, unit: .day))
                        .foregroundStyle(.white.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .annotation(
                            position: .top,
                            spacing: 5,
                            overflowResolution: .init(
                                x: .fit(to: .chart),
                                y: .disabled
                            )
                        ) {
                            ChartValueLabel(value: selectedDay.wordCount)
                        }
                }
            }
            .chartXSelection(value: $rawSelectedDate)
            .chartYScale(domain: 0...(yMaximum + max(yMaximum / 5, 1)))
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 2)) { value in
                    AxisValueLabel(
                        format: .dateTime.month(.abbreviated).day(),
                        collisionResolution: .greedy(minimumSpacing: 8)
                    )
                    .foregroundStyle(.white.opacity(0.5))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine()
                        .foregroundStyle(.white.opacity(0.07))
                    AxisValueLabel()
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .chartPlotStyle { plotArea in
                plotArea
                    .background(.white.opacity(0.025))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .frame(height: 190)
        }
        .insightsCard()
    }
}

private struct ChartValueLabel: View {
    let value: Int

    var body: some View {
        Text("\(value.formatted()) words")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
    }
}

/// Which weekdays carry the dictation habit: a donut of words by weekday over
/// the last sixteen weeks, with angular selection and a center readout.
private struct WeekdayRhythmCard: View {
    private let slices: [WeekdaySlice]
    private let totalWords: Int

    @Environment(\.colorSchemeContrast) private var contrast
    @State private var selectedAngle: Int?

    init(days: [UsageHeatmapDay]) {
        let calendar = UsageMetrics.localCalendar()
        var totals = [Int: Int]()
        for day in days where !day.isFuture && day.wordCount > 0 {
            if let weekday = day.day.weekday(in: calendar) {
                totals[weekday, default: 0] += day.wordCount
            }
        }

        // Sectors need strictly positive values; quiet weekdays are simply
        // absent. Order follows the user's calendar week.
        let symbols = calendar.weekdaySymbols
        let ordered = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
        slices = ordered.compactMap { weekday in
            guard let words = totals[weekday], words > 0 else { return nil }
            return WeekdaySlice(name: symbols[weekday - 1], wordCount: words)
        }
        totalWords = slices.reduce(0) { $0 + $1.wordCount }
    }

    private var selectedSlice: WeekdaySlice? {
        guard let selectedAngle else { return nil }
        var runningTotal = 0
        return slices.first { slice in
            let range = runningTotal..<(runningTotal + slice.wordCount)
            runningTotal += slice.wordCount
            return range.contains(selectedAngle)
        }
    }

    private var busiest: WeekdaySlice? {
        slices.max { $0.wordCount < $1.wordCount }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Weekly Rhythm")
                    .font(.headline)
                if let busiest {
                    Text("\(busiest.name)s carry your dictation")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(contrast == .increased ? 0.76 : 0.52))
                }
            }

            if slices.isEmpty {
                Text("Dictate through a week to see your rhythm here.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(contrast == .increased ? 0.76 : 0.52))
            } else {
                HStack(spacing: 24) {
                    donut
                    breakdown
                }
            }
        }
        .insightsCard()
    }

    private var donut: some View {
        Chart(slices) { slice in
            SectorMark(
                angle: .value("Words Dictated", slice.wordCount),
                innerRadius: .ratio(0.618),
                angularInset: 1.2
            )
            .cornerRadius(4)
            .foregroundStyle(by: .value("Weekday", slice.name))
            .opacity(selectedSlice == nil || selectedSlice?.name == slice.name ? 1 : 0.35)
            .accessibilityLabel(slice.name)
            .accessibilityValue("\(slice.wordCount.formatted()) words dictated")
        }
        .chartAngleSelection(value: $selectedAngle)
        .chartForegroundStyleScale(
            domain: slices.map(\.name),
            range: WeekdaySlice.palette
        )
        .chartLegend(.hidden)
        .chartBackground { _ in
            VStack(spacing: 1) {
                Text(selectedSlice?.name ?? "Total")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
                Text((selectedSlice?.wordCount ?? totalWords).formatted())
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
        }
        .frame(width: 168, height: 168)
    }

    private var breakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(slices.enumerated()), id: \.element.id) { index, slice in
                HStack(spacing: 8) {
                    Circle()
                        .fill(WeekdaySlice.palette[index % WeekdaySlice.palette.count])
                        .frame(width: 7, height: 7)
                    Text(slice.name)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.72))
                    Spacer(minLength: 12)
                    Text(Double(slice.wordCount) / Double(max(totalWords, 1)),
                         format: .percent.precision(.fractionLength(0)))
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WeekdaySlice: Identifiable {
    let name: String
    let wordCount: Int

    var id: String { name }

    /// A cool-range palette that stays inside the app's dark blue language
    /// instead of a rainbow: accent blue drifting toward mint.
    static let palette: [Color] = [
        Color(red: 0.36, green: 0.58, blue: 1.0),
        Color(red: 0.33, green: 0.72, blue: 0.98),
        Color(red: 0.35, green: 0.84, blue: 0.90),
        Color(red: 0.42, green: 0.90, blue: 0.77),
        Color(red: 0.55, green: 0.62, blue: 0.98),
        Color(red: 0.70, green: 0.56, blue: 0.98),
        Color(red: 0.47, green: 0.47, blue: 0.90),
    ]
}

private struct StreakActivityCard: View {
    let summary: UsageSummary
    let days: [UsageHeatmapDay]

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(summary.currentStreak.formatted()) day streak")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                    Text("Sixteen weeks of Direct Dictation")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(contrast == .increased ? 0.76 : 0.52))
                }
                Spacer()
                Text("Longest · \(InsightsFormat.count(summary.longestStreak, singular: "day"))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            ActivityHeatmapChart(days: days)
            ActivityLegend()

            if summary.completedSessions == 0 {
                Text("Complete a Direct Dictation session to see activity here.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(contrast == .increased ? 0.76 : 0.52))
            }
        }
        .insightsCard()
    }
}

private struct ActivityHeatmapChart: View {
    private static let weekCount = 16

    private let chartDays: [HeatmapChartDay]
    private let monthLabels: [Int: String]
    private let monthTicks: [Double]
    private let weekdayLabels: [String]

    @Environment(\.colorSchemeContrast) private var contrast

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
                SettingsTheme.accent,
                .white.opacity(contrast == .increased ? 0.2 : 0.09),
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
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: [0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0]) { value in
                AxisValueLabel {
                    if let row = value.as(Double.self) {
                        Text(weekdayLabels[6 - Int(row)])
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .frame(height: 238)
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
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 6) {
            Text("Less")
            ForEach(1...4, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2)
                    .fill(SettingsTheme.accent.opacity(0.15 + 0.2 * Double(level)))
                    .frame(width: 13, height: 13)
            }
            Text("More")
        }
        .font(.caption2)
        .foregroundStyle(.white.opacity(contrast == .increased ? 0.76 : 0.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Activity ranges from less to more words dictated")
    }
}

private struct InsightsCardModifier: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(SettingsTheme.card)
                    .overlay {
                        LinearGradient(
                            colors: [SettingsTheme.accent.opacity(0.045), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
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

private enum InsightsFormat {
    static func duration(_ duration: TimeInterval) -> String {
        if duration < 60 {
            return "\(Int(duration.rounded()).formatted()) sec"
        }
        if duration < 3_600 {
            return "\(Int((duration / 60).rounded()).formatted()) min"
        }
        return String(format: "%.1f hr", duration / 3_600)
    }

    static func count(_ value: Int, singular: String) -> String {
        "\(value.formatted()) \(value == 1 ? singular : singular + "s")"
    }
}
