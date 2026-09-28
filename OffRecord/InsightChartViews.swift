//
//  InsightChartViews.swift
//  OffRecord
//
//  Soft Swift Charts modules for the Insights tab and Weekly Reflection:
//  mood over time, the last seven days, mood by time of day, and a compact
//  weekly emotional arc. Every chart ships with a one-sentence plain-language
//  summary and an audio-graph descriptor for VoiceOver.
//

import Accessibility
import Charts
import SwiftUI

// MARK: - Mood valence

extension Mood {
    /// Position of a mood on a -1 (heavy) ... 1 (bright) scale so all nine moods
    /// keep their own place on a chart instead of collapsing onto five levels.
    var valence: Double {
        switch self {
        case .excited: return 0.8
        case .happy: return 0.7
        case .grateful: return 0.6
        case .calm: return 0.4
        case .none: return 0
        case .tired: return -0.3
        case .anxious: return -0.5
        case .sad: return -0.6
        case .angry: return -0.7
        }
    }

    /// The selectable mood whose valence is closest to `value`.
    static func nearest(toValence value: Double) -> Mood {
        selectableMoods.min { abs($0.valence - value) < abs($1.valence - value) } ?? .none
    }
}

// MARK: - Time of day

enum InsightTimeOfDay: Int, CaseIterable, Identifiable, Sendable {
    case morning
    case afternoon
    case evening
    case night

    var id: Int { rawValue }

    init(hour: Int) {
        switch hour {
        case 5..<12: self = .morning
        case 12..<17: self = .afternoon
        case 17..<22: self = .evening
        default: self = .night
        }
    }

    var label: String {
        switch self {
        case .morning: return String(localized: "Morning")
        case .afternoon: return String(localized: "Afternoon")
        case .evening: return String(localized: "Evening")
        case .night: return String(localized: "Night")
        }
    }

    var shortLabel: String {
        switch self {
        case .morning: return String(localized: "Morn", comment: "Short chart column label for morning")
        case .afternoon: return String(localized: "Aft", comment: "Short chart column label for afternoon")
        case .evening: return String(localized: "Eve", comment: "Short chart column label for evening")
        case .night: return String(localized: "Night")
        }
    }

    /// Lowercased phrase used inside sentences ("in the evening", "at night").
    var phrase: String {
        switch self {
        case .morning: return String(localized: "in the morning")
        case .afternoon: return String(localized: "in the afternoon")
        case .evening: return String(localized: "in the evening")
        case .night: return String(localized: "at night")
        }
    }
}

// MARK: - Chart data

struct MoodTrendPoint: Identifiable, Equatable, Sendable {
    let date: Date
    let valence: Double
    let mood: Mood
    let entryCount: Int

    var id: Date { date }
}

struct WeekDayActivity: Identifiable, Equatable, Sendable {
    let date: Date
    let entryCount: Int
    let mood: Mood?

    var id: Date { date }
    var hasEntry: Bool { entryCount > 0 }

    var weekdayName: String { date.formatted(.dateTime.weekday(.wide)) }

    var accessibilityValue: String {
        guard hasEntry else { return String(localized: "No entries") }
        let value = String(AttributedString(localized: "^[\(entryCount) entry](inflect: true)").characters)
        guard let mood else { return value }
        return String(localized: "\(value), mostly \(mood.displayName.lowercased())")
    }
}

struct MoodTimeCell: Identifiable, Equatable, Sendable {
    let mood: Mood
    let timeOfDay: InsightTimeOfDay
    let count: Int

    var id: String { "\(mood.rawValue)-\(timeOfDay.rawValue)" }
}

struct InsightChartsSnapshot: Equatable, Sendable {
    /// Daily mood points for the last 90 days, oldest first.
    let moodTrend: [MoodTrendPoint]
    /// The last seven days, oldest first.
    let week: [WeekDayActivity]
    let moodTimeCells: [MoodTimeCell]
    let moodCheckInCount: Int

    static let heatmapMinimumCheckIns = 6
    static let empty = InsightChartsSnapshot(moodTrend: [], week: [], moodTimeCells: [], moodCheckInCount: 0)

    var heatmapIsReady: Bool {
        moodCheckInCount >= Self.heatmapMinimumCheckIns
            && Set(moodTimeCells.map(\.timeOfDay)).count >= 2
    }

    static func make(
        from entries: [JournalEntrySnapshot],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> InsightChartsSnapshot {
        let today = calendar.startOfDay(for: now)
        guard let trendStart = calendar.date(byAdding: .day, value: -89, to: today) else { return .empty }

        var entriesByDay: [Date: [JournalEntrySnapshot]] = [:]
        for entry in entries {
            guard let date = entry.date, date >= trendStart else { continue }
            entriesByDay[calendar.startOfDay(for: date), default: []].append(entry)
        }

        let moodTrend = dailyMoodPoints(entriesByDay: entriesByDay)

        let week: [WeekDayActivity] = (0..<7).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let dayEntries = entriesByDay[date] ?? []
            return WeekDayActivity(date: date, entryCount: dayEntries.count, mood: dominantMood(in: dayEntries))
        }

        var cellCounts: [String: MoodTimeCell] = [:]
        var checkIns = 0
        for dayEntries in entriesByDay.values {
            for entry in dayEntries where entry.mood != .none {
                guard let date = entry.date else { continue }
                checkIns += 1
                let timeOfDay = InsightTimeOfDay(hour: calendar.component(.hour, from: date))
                let key = "\(entry.mood.rawValue)-\(timeOfDay.rawValue)"
                let existing = cellCounts[key]?.count ?? 0
                cellCounts[key] = MoodTimeCell(mood: entry.mood, timeOfDay: timeOfDay, count: existing + 1)
            }
        }

        return InsightChartsSnapshot(
            moodTrend: moodTrend,
            week: week,
            moodTimeCells: cellCounts.values.sorted { lhs, rhs in
                lhs.mood.valence == rhs.mood.valence ? lhs.timeOfDay.rawValue < rhs.timeOfDay.rawValue : lhs.mood.valence > rhs.mood.valence
            },
            moodCheckInCount: checkIns
        )
    }

    /// One point per day that has at least one mood, oldest first.
    static func dailyMoodPoints(entriesByDay: [Date: [JournalEntrySnapshot]]) -> [MoodTrendPoint] {
        entriesByDay.compactMap { day, dayEntries -> MoodTrendPoint? in
            let moods = dayEntries.map(\.mood).filter { $0 != .none }
            guard !moods.isEmpty, let dominant = dominantMood(in: dayEntries) else { return nil }
            let valence = moods.reduce(0) { $0 + $1.valence } / Double(moods.count)
            return MoodTrendPoint(date: day, valence: valence, mood: dominant, entryCount: moods.count)
        }
        .sorted { $0.date < $1.date }
    }

    /// Most frequent mood; ties go to the most recent entry.
    static func dominantMood(in entries: [JournalEntrySnapshot]) -> Mood? {
        let tagged = entries
            .filter { $0.mood != .none }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        guard !tagged.isEmpty else { return nil }
        var counts: [Mood: Int] = [:]
        for entry in tagged { counts[entry.mood, default: 0] += 1 }
        let best = counts.values.max() ?? 0
        return tagged.first { counts[$0.mood] == best }?.mood
    }
}

// MARK: - Shared chrome

struct InsightCardHeader: View {
    let title: String
    let systemImage: String
    var tint: Color = OffRecordColor.textAqua

    var body: some View {
        HStack(spacing: OffRecordSpacing.md) {
            OffRecordIconBubble(systemImage: systemImage, tint: tint, size: 34, iconSize: 15)
            Text(title)
                .font(OffRecordTypography.sectionTitle)
                .foregroundStyle(OffRecordColor.textHeading)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
        }
    }
}

/// The one-sentence, plain-language reading of a chart.
struct InsightChartSummary: View {
    let text: String

    var body: some View {
        Text(text)
            .font(OffRecordTypography.bodySmall)
            .foregroundStyle(OffRecordColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct InsightChartEmptyState: View {
    let systemImage: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: OffRecordSpacing.md) {
            Image(systemName: systemImage)
                .font(OffRecordTypography.titleSmall)
                .foregroundStyle(OffRecordColor.textLavender)
                .accessibilityHidden(true)
            Text(message)
                .font(OffRecordTypography.bodySmall)
                .foregroundStyle(OffRecordColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(OffRecordSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            OffRecordColor.backgroundLavenderTint.opacity(0.7),
            in: RoundedRectangle(cornerRadius: OffRecordRadius.md, style: .continuous)
        )
    }
}

private let insightGridLineStyle = StrokeStyle(lineWidth: 0.6, dash: [3, 4])
private let halfDay: TimeInterval = 12 * 60 * 60

// MARK: - Last seven days

struct WeekActivityChartCard: View {
    let days: [WeekDayActivity]
    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 120

    private var journaledCount: Int { days.filter(\.hasEntry).count }
    private var maxCount: Int { max(1, days.map(\.entryCount).max() ?? 1) }
    private var stubHeight: Double { Double(maxCount) * 0.1 }

    var summary: String {
        switch journaledCount {
        case 0: return String(localized: "No entries in the last 7 days.")
        case days.count: return String(localized: "You journaled every day this week.")
        default: return String(localized: "You journaled on \(journaledCount) of the last \(days.count) days.")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OffRecordSpacing.md) {
            InsightCardHeader(title: String(localized: "Last 7 Days"), systemImage: "calendar", tint: OffRecordColor.textAqua)
            InsightChartSummary(text: summary)

            Chart(days) { day in
                BarMark(
                    x: .value("Day", day.date, unit: .day),
                    y: .value("Entries", day.hasEntry ? Double(day.entryCount) : stubHeight),
                    width: .ratio(0.56)
                )
                .cornerRadius(OffRecordRadius.xs)
                .foregroundStyle(day.hasEntry ? AnyShapeStyle(Self.journaledFill) : AnyShapeStyle(OffRecordColor.textTertiary.opacity(0.2)))
                .annotation(position: .top, spacing: OffRecordSpacing.xs) {
                    if let mood = day.mood {
                        MiniMoodIcon(mood: mood, size: 18, opacity: 0.92)
                    } else if day.hasEntry {
                        Image(systemName: "checkmark")
                            .font(OffRecordTypography.labelSmall)
                            .foregroundStyle(OffRecordColor.textAqua)
                    }
                }
                .accessibilityLabel(day.weekdayName)
                .accessibilityValue(day.accessibilityValue)
            }
            .chartYScale(domain: 0...(Double(maxCount) * 1.45))
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
                        .font(OffRecordTypography.annotation)
                        .foregroundStyle(OffRecordColor.textSecondary)
                }
            }
            .frame(height: chartHeight)
            .accessibilityChartDescriptor(WeekActivityAXDescriptor(days: days, summary: summary))
        }
        .padding()
        .offRecordContentCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfaceMint)
    }

    static let journaledFill = LinearGradient(
        colors: [OffRecordColor.brandAqua, OffRecordColor.brandMint],
        startPoint: .top,
        endPoint: .bottom
    )
}

private struct WeekActivityAXDescriptor: AXChartDescriptorRepresentable {
    let days: [WeekDayActivity]
    let summary: String

    func makeChartDescriptor() -> AXChartDescriptor {
        let names = days.map(\.weekdayName)
        let maxCount = Double(max(1, days.map(\.entryCount).max() ?? 1))
        return AXChartDescriptor(
            title: String(localized: "Last 7 Days"),
            summary: summary,
            xAxis: AXCategoricalDataAxisDescriptor(title: String(localized: "Day", comment: "Chart axis title: day of the week"), categoryOrder: names),
            yAxis: AXNumericDataAxisDescriptor(title: String(localized: "Entries", comment: "Chart axis title: number of journal entries"), range: 0...maxCount, gridlinePositions: []) { value in
                String(AttributedString(localized: "^[\(Int(value)) entry](inflect: true)").characters)
            },
            additionalAxes: [],
            series: [
                AXDataSeriesDescriptor(
                    name: String(localized: "Entries per day"),
                    isContinuous: false,
                    dataPoints: days.map { day in
                        AXDataPoint(x: day.weekdayName, y: Double(day.entryCount), label: day.accessibilityValue)
                    }
                )
            ]
        )
    }
}

// MARK: - Mood over time

enum MoodTrendRange: Int, CaseIterable, Identifiable {
    case twoWeeks = 14
    case month = 30
    case quarter = 90

    var id: Int { rawValue }
    var days: Int { rawValue }

    var title: String {
        switch self {
        case .twoWeeks: return String(localized: "2W", comment: "Segmented control: 2 weeks")
        case .month: return String(localized: "1M", comment: "Segmented control: 1 month")
        case .quarter: return String(localized: "3M", comment: "Segmented control: 3 months")
        }
    }

    var spokenTitle: String {
        switch self {
        case .twoWeeks: return String(localized: "2 weeks")
        case .month: return String(localized: "month", comment: "Spoken time range, as in \"over the last month\"")
        case .quarter: return String(localized: "3 months")
        }
    }

    var axisStrideDays: Int {
        switch self {
        case .twoWeeks: return 4
        case .month: return 9
        case .quarter: return 30
        }
    }
}

enum MoodTrendNarrator {
    static func summary(for points: [MoodTrendPoint], periodPhrase: String) -> String {
        guard !points.isEmpty else {
            return String(localized: "No moods logged \(periodPhrase).")
        }

        let average = points.reduce(0) { $0 + $1.valence } / Double(points.count)
        let tone: String
        switch average {
        case 0.35...: tone = String(localized: "mostly positive")
        case -0.1..<0.35: tone = String(localized: "mixed", comment: "Mood tone, as in \"your moods were mixed\"")
        default: tone = String(localized: "mostly low")
        }

        var counts: [Mood: Int] = [:]
        for point in points { counts[point.mood, default: 0] += point.entryCount }
        let topMood = counts.max { $0.value == $1.value ? $0.key.valence > $1.key.valence : $0.value < $1.value }?.key

        let capitalizedPeriod = periodPhrase.prefix(1).uppercased() + periodPhrase.dropFirst()
        var sentence = String(localized: "\(capitalizedPeriod), your moods were \(tone)")
        if let topMood { sentence += String(localized: ", most often \(topMood.displayName.lowercased())") }

        if points.count >= 4 {
            let half = points.count / 2
            let early = points.prefix(half).reduce(0) { $0 + $1.valence } / Double(half)
            let late = points.suffix(half).reduce(0) { $0 + $1.valence } / Double(half)
            if late - early > 0.25 {
                sentence += String(localized: ", and improving")
            } else if early - late > 0.25 {
                sentence += String(localized: ", and dipping")
            }
        }
        return sentence + String(localized: ".", comment: "Sentence-ending period for the mood trend summary")
    }
}

struct MoodTrendChartCard: View {
    let points: [MoodTrendPoint]
    var now: Date = Date()

    @State private var range: MoodTrendRange = .twoWeeks
    @State private var selectedDate: Date?
    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 176

    private var calendar: Calendar { .current }
    private var today: Date { calendar.startOfDay(for: now) }
    private var rangeStart: Date {
        calendar.date(byAdding: .day, value: -(range.days - 1), to: today) ?? today
    }

    private var visiblePoints: [MoodTrendPoint] {
        points.filter { $0.date >= rangeStart && $0.date <= today }
    }

    private var selectedPoint: MoodTrendPoint? {
        guard let selectedDate else { return nil }
        return visiblePoints.min {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    private var summary: String {
        MoodTrendNarrator.summary(for: visiblePoints, periodPhrase: String(localized: "over the last \(range.spokenTitle)"))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OffRecordSpacing.md) {
            HStack(alignment: .center) {
                InsightCardHeader(title: String(localized: "Mood Over Time"), systemImage: "waveform.path.ecg", tint: OffRecordColor.textAqua)
                Picker("Time range", selection: $range) {
                    ForEach(MoodTrendRange.allCases) { range in
                        Text(range.title)
                            .accessibilityLabel(range.spokenTitle)
                            .tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .accessibilityIdentifier("insights.moodTrend.range")
            }

            InsightChartSummary(text: summary)

            if visiblePoints.isEmpty {
                InsightChartEmptyState(
                    systemImage: "face.smiling",
                    message: String(localized: "Add moods to entries to see them here.")
                )
            } else {
                chart
                    .frame(height: chartHeight)
                    .accessibilityChartDescriptor(
                        MoodTrendAXDescriptor(points: visiblePoints, title: String(localized: "Mood Over Time"), summary: summary)
                    )
            }
        }
        .padding()
        .offRecordContentCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfacePrimary)
        .sensoryFeedback(.selection, trigger: selectedPoint?.id)
        .onChange(of: range) { _, _ in selectedDate = nil }
    }

    private var chart: some View {
        Chart {
            ForEach(visiblePoints) { point in
                AreaMark(
                    x: .value("Date", point.date),
                    yStart: .value("Baseline", -1.0),
                    yEnd: .value("Mood", point.valence)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        colors: [OffRecordColor.brandAqua.opacity(0.34), OffRecordColor.brandAqua.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Mood", point.valence)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(OffRecordColor.brandAqua)
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                PointMark(
                    x: .value("Date", point.date),
                    y: .value("Mood", point.valence)
                )
                .symbol {
                    Circle()
                        .fill(point.mood.color)
                        .overlay(Circle().stroke(OffRecordColor.surfacePrimary, lineWidth: 2))
                        .frame(width: point.id == selectedPoint?.id ? 14 : 9, height: point.id == selectedPoint?.id ? 14 : 9)
                }
                .accessibilityLabel(point.date.formatted(date: .abbreviated, time: .omitted))
                .accessibilityValue(point.mood.displayName)
            }

            if let selectedPoint {
                RuleMark(x: .value("Selected", selectedPoint.date))
                    .foregroundStyle(OffRecordColor.divider)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(
                        position: .top,
                        spacing: 0,
                        overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                    ) {
                        MoodChartCallout(point: selectedPoint)
                    }
            }
        }
        .chartXScale(domain: rangeStart.addingTimeInterval(-halfDay)...today.addingTimeInterval(halfDay))
        .chartYScale(domain: -1...1)
        .chartXSelection(value: $selectedDate)
        .chartYAxis {
            AxisMarks(position: .leading, values: [-0.6, 0.0, 0.7]) { value in
                AxisGridLine(stroke: insightGridLineStyle)
                    .foregroundStyle(OffRecordColor.divider)
                AxisValueLabel {
                    if let valence = value.as(Double.self) {
                        let mood = Self.axisMood(for: valence)
                        MiniMoodIcon(mood: mood, size: 16, opacity: 0.85)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: range.axisStrideDays)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .font(OffRecordTypography.annotation)
                    .foregroundStyle(OffRecordColor.textSecondary)
            }
        }
    }

    private static func axisMood(for valence: Double) -> Mood {
        switch valence {
        case ..<(-0.3): return .sad
        case 0.3...: return .happy
        default: return .none
        }
    }
}

private struct MoodChartCallout: View {
    let point: MoodTrendPoint

    var body: some View {
        VStack(alignment: .leading, spacing: OffRecordSpacing.xxs) {
            Text(point.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                .font(OffRecordTypography.annotation)
                .foregroundStyle(OffRecordColor.textSecondary)
            HStack(spacing: OffRecordSpacing.xs) {
                MiniMoodIcon(mood: point.mood, size: 16, opacity: 1)
                Text(point.mood.displayName)
                    .font(OffRecordTypography.labelSmall)
                    .foregroundStyle(OffRecordColor.textPrimary)
            }
            if point.entryCount > 1 {
                Text("\(point.entryCount) moods")
                    .font(OffRecordTypography.annotation)
                    .foregroundStyle(OffRecordColor.textSecondary)
            }
        }
        .padding(.horizontal, OffRecordSpacing.md)
        .padding(.vertical, OffRecordSpacing.sm)
        .background(OffRecordColor.surfacePrimary, in: RoundedRectangle(cornerRadius: OffRecordRadius.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: OffRecordRadius.sm, style: .continuous)
                .stroke(OffRecordColor.borderSoft, lineWidth: 1)
        )
        .offRecordShadow(.chip)
        .accessibilityElement(children: .combine)
    }
}

private struct MoodTrendAXDescriptor: AXChartDescriptorRepresentable {
    let points: [MoodTrendPoint]
    let title: String
    let summary: String

    func makeChartDescriptor() -> AXChartDescriptor {
        let times = points.map { $0.date.timeIntervalSince1970 }
        let minX = times.min() ?? 0
        let maxX = max(times.max() ?? 1, minX + 1)
        return AXChartDescriptor(
            title: title,
            summary: summary,
            xAxis: AXNumericDataAxisDescriptor(title: String(localized: "Date", comment: "Chart axis title"), range: minX...maxX, gridlinePositions: []) { value in
                Date(timeIntervalSince1970: value).formatted(date: .abbreviated, time: .omitted)
            },
            yAxis: AXNumericDataAxisDescriptor(title: String(localized: "Mood", comment: "Chart axis title: mood level"), range: -1...1, gridlinePositions: [-0.6, 0, 0.7]) { value in
                Mood.nearest(toValence: value).displayName
            },
            additionalAxes: [],
            series: [
                AXDataSeriesDescriptor(
                    name: String(localized: "Daily mood"),
                    isContinuous: true,
                    dataPoints: points.map { point in
                        AXDataPoint(x: point.date.timeIntervalSince1970, y: point.valence, label: point.mood.displayName)
                    }
                )
            ]
        )
    }
}

// MARK: - Mood by time of day

struct MoodTimeHeatmapCard: View {
    let snapshot: InsightChartsSnapshot
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 36

    private var cells: [MoodTimeCell] { snapshot.moodTimeCells }
    private var moods: [Mood] {
        Array(Set(cells.map(\.mood))).sorted { $0.valence > $1.valence }
    }
    private var maxCount: Int { max(1, cells.map(\.count).max() ?? 1) }

    private var summary: String {
        guard let strongest = cells.max(by: { $0.count < $1.count }) else {
            return String(localized: "Add moods to a few entries to see when each shows up.")
        }
        return String(localized: "Over the last 90 days, you’re most often \(strongest.mood.displayName.lowercased()) \(strongest.timeOfDay.phrase).")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OffRecordSpacing.md) {
            InsightCardHeader(title: String(localized: "Mood by Time of Day"), systemImage: "clock", tint: OffRecordColor.textLavender)

            if snapshot.heatmapIsReady {
                InsightChartSummary(text: summary)
                heatmap
                Text("Darker means more often.")
                    .font(OffRecordTypography.annotation)
                    .foregroundStyle(OffRecordColor.textSecondary)
            } else {
                InsightChartEmptyState(
                    systemImage: "square.grid.3x3",
                    message: emptyMessage
                )
            }
        }
        .padding()
        .offRecordContentCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfaceLavender)
    }

    private var emptyMessage: String {
        let remaining = max(0, InsightChartsSnapshot.heatmapMinimumCheckIns - snapshot.moodCheckInCount)
        if remaining > 0 {
            return String(AttributedString(localized: "Add a mood to ^[\(remaining) more entry](inflect: true) to see this.").characters)
        }
        return String(localized: "Journal at different times of day to see this.")
    }

    private var chart: some View {
        Chart(cells) { cell in
            RectangleMark(
                x: .value("Time of day", cell.timeOfDay.label),
                y: .value("Mood", cell.mood.displayName),
                width: .ratio(0.92),
                height: .ratio(0.84)
            )
            .cornerRadius(OffRecordRadius.xs)
            .foregroundStyle(cell.mood.color.opacity(0.3 + 0.7 * Double(cell.count) / Double(maxCount)))
            .annotation(position: .overlay) {
                Text("\(cell.count)")
                    .font(OffRecordTypography.annotation.monospacedDigit())
                    .foregroundStyle(OffRecordColor.textPrimary)
                    .padding(.horizontal, OffRecordSpacing.xs + 2)
                    .padding(.vertical, 1)
                    .background(OffRecordColor.surfacePrimary.opacity(0.85), in: Capsule())
            }
            .accessibilityLabel("\(cell.mood.displayName) \(cell.timeOfDay.phrase)")
            .accessibilityValue(String(AttributedString(localized: "^[\(cell.count) entry](inflect: true)").characters))
        }
        .chartXScale(domain: InsightTimeOfDay.allCases.map(\.label))
        .chartYScale(domain: moods.map(\.displayName))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }

    /// Row and column labels are laid out beside the plot (axes hidden) so each
    /// label lines up exactly with its band.
    private var heatmap: some View {
        HStack(alignment: .top, spacing: OffRecordSpacing.sm) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(moods) { mood in
                    HStack(spacing: OffRecordSpacing.xs) {
                        MiniMoodIcon(mood: mood, size: 16, opacity: 0.9)
                        Text(mood.displayName)
                            .font(OffRecordTypography.annotation)
                            .foregroundStyle(OffRecordColor.textSecondary)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .frame(height: rowHeight, alignment: .leading)
                }
            }
            .accessibilityHidden(true)

            VStack(spacing: OffRecordSpacing.xs) {
                chart
                    .frame(height: CGFloat(moods.count) * rowHeight)
                    .accessibilityChartDescriptor(MoodTimeAXDescriptor(cells: cells, moods: moods, summary: summary))
                HStack(spacing: 0) {
                    ForEach(InsightTimeOfDay.allCases) { time in
                        Text(time.shortLabel)
                            .accessibilityLabel(time.label)
                            .font(OffRecordTypography.annotation)
                            .foregroundStyle(OffRecordColor.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                    }
                }
                .accessibilityHidden(true)
            }
        }
    }
}

private struct MoodTimeAXDescriptor: AXChartDescriptorRepresentable {
    let cells: [MoodTimeCell]
    let moods: [Mood]
    let summary: String

    func makeChartDescriptor() -> AXChartDescriptor {
        let maxCount = Double(max(1, cells.map(\.count).max() ?? 1))
        return AXChartDescriptor(
            title: String(localized: "Mood by Time of Day"),
            summary: summary,
            xAxis: AXCategoricalDataAxisDescriptor(title: String(localized: "Time of day"), categoryOrder: InsightTimeOfDay.allCases.map(\.label)),
            yAxis: AXNumericDataAxisDescriptor(title: String(localized: "Entries", comment: "Chart axis title: number of journal entries"), range: 0...maxCount, gridlinePositions: []) { value in
                String(AttributedString(localized: "^[\(Int(value)) entry](inflect: true)").characters)
            },
            additionalAxes: [],
            series: moods.map { mood in
                AXDataSeriesDescriptor(
                    name: mood.displayName,
                    isContinuous: false,
                    dataPoints: InsightTimeOfDay.allCases.map { time in
                        let count = cells.first { $0.mood == mood && $0.timeOfDay == time }?.count ?? 0
                        return AXDataPoint(x: time.label, y: Double(count))
                    }
                )
            }
        )
    }
}

// MARK: - Weekly emotional arc

/// Compact seven-day mood line used by the Weekly Reflection report.
struct WeeklyMoodArcChart: View {
    let points: [MoodTrendPoint]
    let periodStart: Date
    let periodEnd: Date
    var summary: String
    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 112

    private var domain: ClosedRange<Date> {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: periodStart)
        let end = max(calendar.startOfDay(for: periodEnd), start)
        return start.addingTimeInterval(-halfDay)...end.addingTimeInterval(halfDay)
    }

    var body: some View {
        if points.isEmpty {
            InsightChartEmptyState(
                systemImage: "face.smiling",
                message: String(localized: "No moods logged this week.")
            )
        } else {
            Chart {
                ForEach(points) { point in
                    AreaMark(
                        x: .value("Day", point.date),
                        yStart: .value("Baseline", -1.0),
                        yEnd: .value("Mood", point.valence)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [OffRecordColor.brandAqua.opacity(0.3), OffRecordColor.brandAqua.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(x: .value("Day", point.date), y: .value("Mood", point.valence))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(OffRecordColor.brandAqua)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                    PointMark(x: .value("Day", point.date), y: .value("Mood", point.valence))
                        .symbol {
                            MiniMoodIcon(mood: point.mood, size: 20, opacity: 1)
                        }
                        .accessibilityLabel(point.date.formatted(.dateTime.weekday(.wide)))
                        .accessibilityValue(point.mood.displayName)
                }
            }
            .chartXScale(domain: domain)
            .chartYScale(domain: -1...1)
            .chartYAxis {
                AxisMarks(values: [0.0]) { _ in
                    AxisGridLine(stroke: insightGridLineStyle)
                        .foregroundStyle(OffRecordColor.divider)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                        .font(OffRecordTypography.annotation)
                        .foregroundStyle(OffRecordColor.textSecondary)
                }
            }
            .frame(height: chartHeight)
            .accessibilityChartDescriptor(
                MoodTrendAXDescriptor(points: points, title: String(localized: "Mood", comment: "Chart title: mood over the week"), summary: summary)
            )
        }
    }
}
