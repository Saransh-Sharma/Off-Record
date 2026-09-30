//
//  YearInPixelsWidget.swift
//  OffRecordWidget
//
//  A large widget with one pixel per day of the current year, colored by that
//  day's mood. Built from dates and mood values only.
//

import SwiftUI
import WidgetKit

struct YearInPixelsSummary {
    let year: Int
    let journaledDays: Int
    let topMood: Mood?

    init(entry: JournalWidgetEntry, calendar: Calendar = .current) {
        let year = calendar.component(.year, from: entry.date)
        let prefix = String(format: "%04d-", year)
        var count = 0
        var moodCounts: [Mood: Int] = [:]
        for (key, raw) in entry.snapshot.days where key.hasPrefix(prefix) {
            count += 1
            if let mood = Mood(rawValue: raw), mood != .none {
                moodCounts[mood, default: 0] += 1
            }
        }
        self.year = year
        self.journaledDays = count
        self.topMood = moodCounts.max { lhs, rhs in
            lhs.value == rhs.value ? lhs.key.rawValue > rhs.key.rawValue : lhs.value < rhs.value
        }?.key
    }
}

struct YearInPixelsView: View {
    let entry: JournalWidgetEntry

    private var summary: YearInPixelsSummary { YearInPixelsSummary(entry: entry) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            YearPixelGrid(entry: entry, year: summary.year)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement()
                .accessibilityLabel(accessibilitySummary)
            legend
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Year in Pixels")
                    .font(OffRecordWidgetTypography.eyebrow)
                    .foregroundStyle(OffRecordColor.textSecondary)
                Text(String(summary.year))
                    .font(OffRecordWidgetTypography.titleMedium)
                    .foregroundStyle(OffRecordColor.textHeading)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(summary.journaledDays)")
                    .font(OffRecordWidgetTypography.numberSmall)
                    .foregroundStyle(OffRecordColor.textHeading)
                Text(summary.topMood.map { "\(dayUnit) · mostly \($0.displayName.lowercased())" } ?? "\(dayUnit) journaled")
                    .font(OffRecordWidgetTypography.micro)
                    .foregroundStyle(OffRecordColor.textSecondary)
                    .lineLimit(1)
            }
        }
    }

    private var legend: some View {
        let moods = Mood.selectable
        return Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
            GridRow {
                ForEach(moods.prefix(4), id: \.self) { LegendItem(mood: $0) }
            }
            GridRow {
                ForEach(moods.suffix(4), id: \.self) { LegendItem(mood: $0) }
            }
        }
        .accessibilityHidden(true)
    }

    /// The unit under the day count, which is drawn as its own larger number.
    private var dayUnit: String {
        summary.journaledDays == 1 ? String(localized: "day") : String(localized: "days")
    }

    private var accessibilitySummary: String {
        var text = String(AttributedString(localized: "^[\(summary.journaledDays) day](inflect: true) journaled in \(String(summary.year))").characters)
        if let mood = summary.topMood {
            text += ", most often \(mood.displayName)"
        }
        return text
    }
}

private struct LegendItem: View {
    let mood: Mood

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(mood.color)
                .frame(width: 7, height: 7)
            Text(mood.displayName)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(OffRecordColor.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

/// Twelve rows (months) by up to 31 columns (days), drawn in one Canvas.
struct YearPixelGrid: View {
    let entry: JournalWidgetEntry
    let year: Int

    private static let monthInitials = ["J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"]

    var body: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: entry.date)
        let snapshot = entry.snapshot

        Canvas { context, size in
            let labelWidth: CGFloat = 12
            let gapX: CGFloat = 2
            let gapY: CGFloat = 4
            let columns: CGFloat = 31
            let cellWidth = max(2, (size.width - labelWidth - 4 - (columns - 1) * gapX) / columns)
            let rowHeight = max(2, (size.height - 11 * gapY) / 12)
            let cellHeight = min(rowHeight, cellWidth * 1.8)
            let gridHeight = cellHeight * 12 + gapY * 11
            let originY = max(0, (size.height - gridHeight) / 2)
            let radius = min(cellWidth, cellHeight) * 0.3

            for month in 1...12 {
                let rowY = originY + CGFloat(month - 1) * (cellHeight + gapY)
                context.draw(
                    Text(Self.monthInitials[month - 1])
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundColor(OffRecordColor.textSecondary),
                    at: CGPoint(x: labelWidth / 2, y: rowY + cellHeight / 2),
                    anchor: .center
                )

                guard let firstOfMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
                      let dayRange = calendar.range(of: .day, in: .month, for: firstOfMonth) else { continue }

                for day in dayRange {
                    guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { continue }
                    let x = labelWidth + 4 + CGFloat(day - 1) * (cellWidth + gapX)
                    let rect = CGRect(x: x, y: rowY, width: cellWidth, height: cellHeight)
                    let path = Path(roundedRect: rect, cornerRadius: radius)

                    let fill: Color
                    if date > today {
                        fill = OffRecordColor.pixelEmpty.opacity(0.45)
                    } else if let raw = snapshot.mood(on: date, calendar: calendar),
                              let mood = Mood(rawValue: raw), mood != .none {
                        fill = mood.color
                    } else if snapshot.hasEntry(on: date, calendar: calendar) {
                        fill = OffRecordColor.pixelNeutral
                    } else {
                        fill = OffRecordColor.pixelEmpty
                    }
                    context.fill(path, with: .color(fill))

                    if date == today {
                        context.stroke(
                            Path(roundedRect: rect.insetBy(dx: -1, dy: -1), cornerRadius: radius + 1),
                            with: .color(OffRecordColor.textHeading),
                            lineWidth: 1.2
                        )
                    }
                }
            }
        }
    }
}

struct YearInPixelsWidget: Widget {
    let kind: String = "YearInPixelsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: JournalSnapshotProvider()) { entry in
            YearInPixelsView(entry: entry)
                .offRecordWidgetBackground()
                .widgetURL(OffRecordWidgetRoute.timeline)
        }
        .configurationDisplayName("Year in Pixels")
        .description("See your year, colored by mood.")
        .supportedFamilies([.systemLarge, .systemExtraLarge])
    }
}

#Preview("Year in Pixels", as: .systemLarge) {
    YearInPixelsWidget()
} timeline: {
    JournalWidgetEntry.sample
}
