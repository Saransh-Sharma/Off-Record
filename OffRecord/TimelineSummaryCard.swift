//
//  TimelineSummaryCard.swift
//  OffRecord
//

import SwiftUI

struct MonthSummaryCard: View {
    let entries: [DiaryEntry]

    private var totalEntries: Int { entries.count }

    private var totalWords: Int {
        entries.reduce(0) { $0 + TimelineEntryMetrics.wordCount(for: $1) }
    }

    private var chartValues: [Int] {
        MonthlyWordsChartSeries.values(from: entries)
    }

    var body: some View {
        GeometryReader { proxy in
            let statsWidth = min(max(proxy.size.width * 0.42, 168), 250)

            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("This month")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(OffRecordColor.textBrand.opacity(0.86))
                        .lineLimit(1)

                    HStack(spacing: 18) {
                        summaryStat(value: "\(totalEntries)", label: "Entries")
                            .frame(width: 56, alignment: .leading)

                        Rectangle()
                            .fill(OffRecordColor.borderWarm.opacity(0.9))
                            .frame(width: 1, height: 56)

                        summaryStat(value: totalWords.formatted(), label: "Words")
                            .frame(minWidth: 78, alignment: .leading)
                    }
                }
                .frame(width: statsWidth, alignment: .leading)
                .layoutPriority(1)

                MonthlyWordsChart(values: chartValues)
                    .frame(maxWidth: .infinity)
                    .frame(height: TimelineDesign.summaryChartHeight)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
        }
        .frame(height: TimelineDesign.summaryCardHeight)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(OffRecordColor.surfacePrimary.opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: 28)
                        .stroke(OffRecordColor.borderWarm.opacity(0.84), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.052), radius: 22, x: 0, y: 11)
        )
    }

    private func summaryStat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .font(.system(size: 31, weight: .bold, design: .rounded))
                .foregroundStyle(OffRecordColor.textBrand)
                .minimumScaleFactor(0.66)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(OffRecordColor.textSecondary)
                .lineLimit(1)
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

struct MonthlyWordsChart: View {
    let values: [Int]

    var body: some View {
        Canvas { context, size in
            let normalizedValues = values.isEmpty ? [0, 0] : values
            let maxValue = max(normalizedValues.max() ?? 1, 1)
            let points = normalizedValues.enumerated().map { index, value in
                let progress = normalizedValues.count <= 1 ? 0 : Double(index) / Double(normalizedValues.count - 1)
                let x = size.width * progress
                let usableHeight = size.height - 10
                let y = size.height - CGFloat(value) / CGFloat(maxValue) * usableHeight - 5
                return CGPoint(x: x, y: y)
            }

            for y in [0.18, 0.5, 0.82].map({ size.height * $0 }) {
                var gridPath = Path()
                gridPath.move(to: CGPoint(x: 0, y: y))
                gridPath.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(
                    gridPath,
                    with: .color(OffRecordColor.borderWarm.opacity(0.48)),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 5])
                )
            }

            guard points.count >= 2 else { return }

            let guideIndices = Set([points.count / 3, max(0, (points.count * 2) / 3)].filter { points.indices.contains($0) })
            for index in guideIndices {
                let point = points[index]
                var guidePath = Path()
                guidePath.move(to: CGPoint(x: point.x, y: point.y))
                guidePath.addLine(to: CGPoint(x: point.x, y: size.height))
                context.stroke(
                    guidePath,
                    with: .color(OffRecordColor.brandLavenderDark.opacity(0.18)),
                    style: StrokeStyle(lineWidth: 1, dash: [2, 3])
                )
            }

            var areaPath = Path()
            areaPath.move(to: CGPoint(x: points[0].x, y: size.height))
            points.forEach { areaPath.addLine(to: $0) }
            areaPath.addLine(to: CGPoint(x: points[points.count - 1].x, y: size.height))
            areaPath.closeSubpath()
            context.fill(
                areaPath,
                with: .linearGradient(
                    Gradient(colors: [
                        OffRecordColor.brandLavender.opacity(0.34),
                        OffRecordColor.brandLavender.opacity(0.05)
                    ]),
                    startPoint: CGPoint(x: size.width / 2, y: 0),
                    endPoint: CGPoint(x: size.width / 2, y: size.height)
                )
            )

            var linePath = Path()
            linePath.move(to: points[0])
            points.dropFirst().forEach { linePath.addLine(to: $0) }
            context.stroke(
                linePath,
                with: .color(OffRecordColor.brandLavenderDark.opacity(0.78)),
                style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
            )

            for index in points.indices where normalizedValues[index] > 0 {
                let point = points[index]
                let rect = CGRect(x: point.x - 4.5, y: point.y - 4.5, width: 9, height: 9)
                context.fill(Path(ellipseIn: rect), with: .color(OffRecordColor.brandPeach.opacity(0.82)))
                context.stroke(Path(ellipseIn: rect), with: .color(OffRecordColor.brandLavenderDark.opacity(0.72)), lineWidth: 1)
            }
        }
    }
}
