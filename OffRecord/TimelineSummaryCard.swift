//
//  TimelineSummaryCard.swift
//  OffRecord
//

import Charts
import SwiftUI

struct MonthSummaryCard: View {
    let title: String
    let entries: [DiaryEntry]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var totalEntries: Int { entries.count }

    private var totalWords: Int {
        entries.reduce(0) { $0 + TimelineEntryMetrics.wordCount(for: $1) }
    }

    private var chartValues: [Int] {
        MonthlyWordsChartSeries.values(from: entries)
    }

    var body: some View {
        // AnyLayout keeps the same stats as the arrangement changes, so they scale with
        // Dynamic Type; large sizes put the chart under the numbers.
        let layout = dynamicTypeSize >= .xxLarge
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: OffRecordSpacing.lg))
            : AnyLayout(HStackLayout(alignment: .center, spacing: OffRecordSpacing.lg))
        layout {
            stats
                .layoutPriority(1)
            MonthlyWordsChart(values: chartValues)
                .frame(minWidth: 110, maxWidth: .infinity)
                .frame(height: TimelineDesign.summaryChartHeight)
        }
        .padding(.horizontal, OffRecordSpacing.xl)
        .padding(.vertical, OffRecordSpacing.xl)
        .offRecordContentCard(cornerRadius: OffRecordRadius.xl, fill: OffRecordColor.surfacePrimary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(AttributedString(localized: "\(title): ^[\(totalEntries) entry](inflect: true), ^[\(totalWords) word](inflect: true)").characters))
    }

    private var stats: some View {
        VStack(alignment: .leading, spacing: OffRecordSpacing.md) {
            Text(title)
                .font(OffRecordTypography.bodyMedium)
                .foregroundStyle(OffRecordColor.textBrand.opacity(0.86))
            HStack(spacing: OffRecordSpacing.lg) {
                summaryStat(value: "\(totalEntries)", label: totalEntries == 1 ? "Entry" : "Entries")
                Rectangle()
                    .fill(OffRecordColor.borderWarm.opacity(0.9))
                    .frame(width: 1, height: 44)
                summaryStat(value: totalWords.formatted(), label: "Words")
            }
        }
    }

    private func summaryStat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: OffRecordSpacing.xs) {
            Text(value)
                .font(OffRecordTypography.numberMedium)
                .foregroundStyle(OffRecordColor.textBrand)
                .contentTransition(.numericText())
                .fixedSize(horizontal: false, vertical: true)
            Text(label)
                .font(OffRecordTypography.metadata)
                .foregroundStyle(OffRecordColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private enum MonthlyWordsChartSeries {
    static func values(from entries: [DiaryEntry], maxPoints: Int = 10) -> [Int] {
        let calendar = Calendar.current
        let wordsByDay = Dictionary(grouping: entries) { entry -> Int in
            guard let date = entry.date else { return 0 }
            return calendar.component(.day, from: date)
        }
        .mapValues { dayEntries in
            dayEntries.reduce(0) { $0 + TimelineEntryMetrics.wordCount(for: $1) }
        }

        let nonZeroValues = wordsByDay
            .keys
            .sorted()
            .compactMap { day -> Int? in
                guard let words = wordsByDay[day], words > 0 else { return nil }
                return words
            }

        guard !nonZeroValues.isEmpty else { return [0, 0] }
        guard nonZeroValues.count > 1 else { return [0, nonZeroValues[0], nonZeroValues[0]] }
        guard nonZeroValues.count > maxPoints else { return smooth(nonZeroValues) }

        let bucketSize = Double(nonZeroValues.count) / Double(maxPoints)
        let sampledValues = (0..<maxPoints).map { bucket in
            let start = Int((Double(bucket) * bucketSize).rounded(.down))
            let end = min(nonZeroValues.count, Int((Double(bucket + 1) * bucketSize).rounded(.down)))
            let range = start..<max(end, start + 1)
            return range.reduce(0) { $0 + nonZeroValues[$1] }
        }
        return smooth(sampledValues)
    }

    private static func smooth(_ values: [Int]) -> [Int] {
        guard values.count > 4 else { return values }
        return values.indices.map { index in
            if index == 0 || index == values.count - 1 {
                return values[index]
            }
            let previous = Double(values[index - 1])
            let current = Double(values[index])
            let next = Double(values[index + 1])
            return Int(previous * 0.25 + current * 0.5 + next * 0.25)
        }
    }
}

/// Soft words-per-day trend for the month.
struct MonthlyWordsChart: View {
    let values: [Int]

    private var points: [(index: Int, value: Int)] {
        let values = values.isEmpty ? [0, 0] : values
        return values.enumerated().map { ($0.offset, $0.element) }
    }

    var body: some View {
        Chart(points, id: \.index) { point in
            AreaMark(
                x: .value("Day", point.index),
                y: .value("Words", point.value)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(
                LinearGradient(
                    colors: [OffRecordColor.brandLavender.opacity(0.34), OffRecordColor.brandLavender.opacity(0.04)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            LineMark(
                x: .value("Day", point.index),
                y: .value("Words", point.value)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(OffRecordColor.textLavender.opacity(0.85))
            .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            if point.value > 0 {
                PointMark(
                    x: .value("Day", point.index),
                    y: .value("Words", point.value)
                )
                .symbolSize(28)
                .foregroundStyle(OffRecordColor.brandPeach)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .accessibilityHidden(true)
    }
}
