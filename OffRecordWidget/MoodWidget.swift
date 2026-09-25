//
//  MoodWidget.swift
//  OffRecordWidget
//
//  Today's mood at a glance, and an interactive medium widget that logs a
//  mood on today's entry without opening the app (via LogMoodIntent, which
//  runs in the app's process).
//

import AppIntents
import SwiftUI
import WidgetKit

struct MoodWidgetView: View {
    let entry: JournalWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemMedium:
            MoodPickerView(entry: entry)
        default:
            SmallMoodView(entry: entry)
        }
    }
}

struct TodayMoodBadge: View {
    let mood: Mood?
    var diameter: CGFloat = 44

    var body: some View {
        ZStack {
            Circle()
                .fill((mood?.color ?? OffRecordColor.pixelEmpty).opacity(mood == nil ? 1 : 0.32))
            Image(systemName: mood?.icon ?? "face.dashed")
                .font(.system(size: diameter * 0.44, weight: .semibold))
                .foregroundStyle(mood?.readableColor ?? OffRecordColor.textSecondary)
        }
        .frame(width: diameter, height: diameter)
        .widgetAccentable()
        .accessibilityHidden(true)
    }
}

struct SmallMoodView: View {
    let entry: JournalWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Today's mood")
                .font(OffRecordWidgetTypography.eyebrow)
                .foregroundStyle(OffRecordColor.textSecondary)

            Spacer(minLength: 0)

            TodayMoodBadge(mood: entry.todayMood)
                .invalidatableContent()
            Text(entry.todayMood?.displayName ?? "How are you?")
                .font(OffRecordWidgetTypography.titleSmall)
                .foregroundStyle(entry.todayMood?.readableColor ?? OffRecordColor.textHeading)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .invalidatableContent()

            Spacer(minLength: 0)

            WeekDots(days: entry.lastSevenDays)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct MoodPickerView: View {
    let entry: JournalWidgetEntry

    private let rows: [[Mood]] = [
        [.happy, .calm, .grateful, .excited],
        [.tired, .anxious, .sad, .angry]
    ]

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Mood")
                    .font(OffRecordWidgetTypography.eyebrow)
                    .foregroundStyle(OffRecordColor.textSecondary)
                Spacer(minLength: 0)
                TodayMoodBadge(mood: entry.todayMood, diameter: 40)
                    .invalidatableContent()
                Text(entry.todayMood?.displayName ?? "Tap one")
                    .font(OffRecordWidgetTypography.cardTitle)
                    .foregroundStyle(entry.todayMood?.readableColor ?? OffRecordColor.textHeading)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .invalidatableContent()
                Text("today")
                    .font(OffRecordWidgetTypography.micro)
                    .foregroundStyle(OffRecordColor.textSecondary)
            }
            .frame(width: 76, alignment: .leading)

            Grid(horizontalSpacing: 4, verticalSpacing: 6) {
                ForEach(rows, id: \.self) { row in
                    GridRow {
                        ForEach(row, id: \.self) { mood in
                            MoodButton(mood: mood, isSelected: entry.todayMood == mood)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct MoodButton: View {
    let mood: Mood
    let isSelected: Bool

    var body: some View {
        if let value = mood.intentValue {
            Button(intent: LogMoodIntent(mood: value)) {
                VStack(spacing: 3) {
                    ZStack {
                        Circle()
                            .fill(mood.color.opacity(isSelected ? 1 : 0.28))
                        Image(systemName: mood.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(isSelected ? OffRecordColor.textPrimary : mood.readableColor)
                    }
                    .frame(width: 32, height: 32)
                    .overlay {
                        if isSelected {
                            Circle().strokeBorder(mood.readableColor, lineWidth: 1.5)
                        }
                    }
                    .widgetAccentable()

                    Text(mood.displayName)
                        .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? OffRecordColor.textHeading : OffRecordColor.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Log \(mood.displayName)")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }
}

struct MoodWidget: Widget {
    let kind: String = "MoodWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: JournalSnapshotProvider()) { entry in
            MoodWidgetView(entry: entry)
                .offRecordWidgetBackground()
                .widgetURL(OffRecordWidgetRoute.today)
        }
        .configurationDisplayName("Mood")
        .description("See today's mood, or log one right from the Home Screen.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview("Mood - Small", as: .systemSmall) {
    MoodWidget()
} timeline: {
    JournalWidgetEntry.sample
    JournalWidgetEntry(date: Date(), snapshot: .empty)
}

#Preview("Mood - Medium", as: .systemMedium) {
    MoodWidget()
} timeline: {
    JournalWidgetEntry.sample
    JournalWidgetEntry(date: Date(), snapshot: .empty)
}
