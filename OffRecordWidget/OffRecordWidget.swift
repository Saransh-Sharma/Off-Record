//
//  OffRecordWidget.swift
//  OffRecordWidget
//
//  Home Screen and Lock Screen widgets, the Record control, and the capture
//  Live Activity. Widgets read the metadata-only snapshot the app writes to
//  the App Group (see OffRecordSystemShared/WidgetSnapshot.swift); they never
//  open the journal store and never show journal text.
//

import AppIntents
import SwiftUI
import WidgetKit
import os.log

let widgetLogger = Logger(subsystem: "com.singularity.offrecord.widget", category: "OffRecordWidget")

enum OffRecordWidgetRoute {
    static let today = URL(string: "offrecord://today")
    static let record = URL(string: "offrecord://record")
    static let timeline = URL(string: "offrecord://timeline")
    static let insights = URL(string: "offrecord://weekly-reflection/current")
}

// MARK: - Timeline

struct WidgetDay: Hashable {
    let date: Date
    let hasEntry: Bool
    let mood: Mood?
}

struct JournalWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot

    var hasEntryToday: Bool { snapshot.hasEntry(on: date) }
    var streak: Int { snapshot.streak(asOf: date) }
    var totalEntries: Int { snapshot.totalEntries }
    var todayWordCount: Int { snapshot.todayWordCount(asOf: date) }
    var todayHasVoice: Bool { snapshot.todayHasVoice(asOf: date) }

    var todayMood: Mood? {
        guard let raw = snapshot.mood(on: date), let mood = Mood(rawValue: raw), mood != .none else { return nil }
        return mood
    }

    /// The last seven days, oldest first, with whether each had an entry.
    var lastSevenDays: [WidgetDay] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: date)
        return (0..<7).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let mood = snapshot.mood(on: day).flatMap(Mood.init(rawValue:))
            return WidgetDay(date: day, hasEntry: snapshot.hasEntry(on: day), mood: mood == Mood.none ? nil : mood)
        }
    }

    static let sample = JournalWidgetEntry(date: Date(), snapshot: .sample)
}

struct JournalSnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> JournalWidgetEntry {
        .sample
    }

    func getSnapshot(in context: Context, completion: @escaping (JournalWidgetEntry) -> Void) {
        if context.isPreview {
            completion(WidgetSnapshotStore.load().map { JournalWidgetEntry(date: Date(), snapshot: $0) } ?? .sample)
        } else {
            completion(JournalWidgetEntry(date: Date(), snapshot: WidgetSnapshotStore.load() ?? .empty))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<JournalWidgetEntry>) -> Void) {
        let snapshot = WidgetSnapshotStore.load() ?? .empty
        let calendar = Calendar.current
        let now = Date()
        var entries = [JournalWidgetEntry(date: now, snapshot: snapshot)]
        // Streaks and "today" flip at midnight; render that change without waiting for the app.
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
        if let tomorrow {
            entries.append(JournalWidgetEntry(date: tomorrow, snapshot: snapshot))
        }
        let refresh = tomorrow.flatMap { calendar.date(byAdding: .day, value: 1, to: $0) } ?? now.addingTimeInterval(6 * 3600)
        completion(Timeline(entries: entries, policy: .after(refresh)))
    }
}

extension WidgetSnapshot {
    /// Deterministic sample data for placeholders, previews, and the widget gallery.
    static let sample: WidgetSnapshot = {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let moods = ["calm", "happy", "grateful", "", "tired", "calm", "excited", "anxious", "happy", "sad", "calm", "grateful"]
        var days: [String: String] = [:]
        for offset in 0..<260 {
            // Skip a few days so the sample shows gaps.
            if offset > 11 && (offset % 7 == 3 || offset % 11 == 5) { continue }
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            days[WidgetDayKey.key(for: day, calendar: calendar)] = moods[(offset * 7 + offset / 5) % moods.count]
        }
        return WidgetSnapshot(
            days: days,
            totalEntries: days.count,
            todayKey: WidgetDayKey.key(for: today, calendar: calendar),
            todayWordCount: 142,
            todayHasVoice: true
        )
    }()
}

// MARK: - Mood (mirrors MoodDialKit.Mood raw values)

enum Mood: String, CaseIterable {
    case none = ""
    case happy = "happy"
    case calm = "calm"
    case grateful = "grateful"
    case excited = "excited"
    case tired = "tired"
    case anxious = "anxious"
    case sad = "sad"
    case angry = "angry"

    static var selectable: [Mood] { allCases.filter { $0 != .none } }

    var displayName: String {
        switch self {
        case .none: return String(localized: "No mood")
        case .happy: return String(localized: "Happy")
        case .calm: return String(localized: "Calm")
        case .grateful: return String(localized: "Grateful")
        case .excited: return String(localized: "Excited")
        case .tired: return String(localized: "Tired")
        case .anxious: return String(localized: "Anxious")
        case .sad: return String(localized: "Sad")
        case .angry: return String(localized: "Angry")
        }
    }

    var icon: String {
        switch self {
        case .none: return "circle.dashed"
        case .happy: return "sun.max.fill"
        case .calm: return "leaf.fill"
        case .grateful: return "heart.fill"
        case .excited: return "star.fill"
        case .tired: return "moon.zzz.fill"
        case .anxious: return "wind"
        case .sad: return "cloud.rain.fill"
        case .angry: return "flame.fill"
        }
    }

    var color: Color {
        switch self {
        case .none: return OffRecordColor.textSecondary
        case .happy: return OffRecordColor.moodGreat
        case .calm: return OffRecordColor.moodCalm
        case .grateful: return OffRecordColor.moodGood
        case .excited: return OffRecordColor.moodOkay
        case .tired: return OffRecordColor.moodTired
        case .anxious: return OffRecordColor.moodAnxious
        case .sad: return OffRecordColor.moodSad
        case .angry: return OffRecordColor.moodAngry
        }
    }

    var readableColor: Color {
        switch self {
        case .none: return OffRecordColor.textSecondary
        case .happy: return OffRecordColor.textMint
        case .calm: return OffRecordColor.textAqua
        case .grateful: return OffRecordColor.textSage
        case .excited: return OffRecordColor.textYellow
        case .tired: return OffRecordColor.textPeach
        case .anxious: return OffRecordColor.textLavender
        case .sad: return OffRecordColor.textBlush
        case .angry: return OffRecordColor.textCoral
        }
    }

    var intentValue: JournalMoodIntentValue? {
        JournalMoodIntentValue(rawValue: rawValue)
    }
}

// MARK: - Shared pieces

/// Formats today's metadata ("142 words · recording") without any journal text.
func todayMetadataLine(for entry: JournalWidgetEntry) -> String? {
    var parts: [String] = []
    if entry.todayWordCount > 0 {
        parts.append(String(AttributedString(localized: "^[\(entry.todayWordCount) word](inflect: true)").characters))
    }
    if entry.todayHasVoice {
        parts.append("recording")
    }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
}

struct RecordIntentButton<Label: View>: View {
    @ViewBuilder var label: () -> Label

    var body: some View {
        Button(intent: RecordJournalIntent()) {
            label()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Record")
    }
}

struct RecordGlyph: View {
    var diameter: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(OffRecordColor.recordFill)
            Image(systemName: "mic.fill")
                .font(.system(size: diameter * 0.4, weight: .semibold))
                .foregroundStyle(OffRecordColor.textOnAccent)
        }
        .frame(width: diameter, height: diameter)
        .widgetAccentable()
    }
}

struct StreakBadge: View {
    let streak: Int

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "flame.fill")
                .foregroundStyle(streak > 0 ? OffRecordColor.textWarm : OffRecordColor.textSecondary)
                .widgetAccentable()
            Text("^[\(streak) day](inflect: true)")
                .foregroundStyle(OffRecordColor.textSecondary)
        }
        .font(OffRecordWidgetTypography.micro)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(streak)-day streak")
    }
}

// MARK: - Today widget

struct TodayWidgetView: View {
    let entry: JournalWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemMedium:
            TodayMediumView(entry: entry)
        case .accessoryCircular:
            TodayCircularView(entry: entry)
        case .accessoryRectangular:
            TodayRectangularView(entry: entry)
        case .accessoryInline:
            TodayInlineView(entry: entry)
        default:
            TodaySmallView(entry: entry)
        }
    }
}

struct TodaySmallView: View {
    let entry: JournalWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today")
                    .font(OffRecordWidgetTypography.eyebrow)
                    .foregroundStyle(OffRecordColor.textSecondary)
                Spacer(minLength: 4)
                Text(entry.date, format: .dateTime.weekday(.abbreviated).day())
                    .font(OffRecordWidgetTypography.micro)
                    .foregroundStyle(OffRecordColor.textSecondary)
            }

            Spacer(minLength: 0)

            if entry.hasEntryToday {
                statusIcon
                Text(entry.todayMood?.displayName ?? "Journaled")
                    .font(OffRecordWidgetTypography.titleSmall)
                    .foregroundStyle(OffRecordColor.textHeading)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let line = todayMetadataLine(for: entry) {
                    Text(line)
                        .font(OffRecordWidgetTypography.metadata)
                        .foregroundStyle(OffRecordColor.textSecondary)
                        .lineLimit(1)
                }
            } else {
                RecordIntentButton {
                    HStack(spacing: 8) {
                        RecordGlyph(diameter: 40)
                        Text("Record")
                            .font(OffRecordWidgetTypography.cardTitle)
                            .foregroundStyle(OffRecordColor.textHeading)
                    }
                }
                Text("Nothing yet today")
                    .font(OffRecordWidgetTypography.metadata)
                    .foregroundStyle(OffRecordColor.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
            StreakBadge(streak: entry.streak)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var statusIcon: some View {
        let mood = entry.todayMood
        return ZStack {
            Circle().fill((mood?.color ?? OffRecordColor.brandSage).opacity(0.28))
            Image(systemName: mood?.icon ?? "checkmark")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(mood?.readableColor ?? OffRecordColor.textSage)
        }
        .frame(width: 36, height: 36)
        .widgetAccentable()
        .accessibilityHidden(true)
    }
}

struct TodayMediumView: View {
    let entry: JournalWidgetEntry

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.date, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                    .font(OffRecordWidgetTypography.eyebrow)
                    .foregroundStyle(OffRecordColor.textSecondary)
                    .lineLimit(1)

                Text(headline)
                    .font(OffRecordWidgetTypography.titleSmall)
                    .foregroundStyle(OffRecordColor.textHeading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)

                if let mood = entry.todayMood {
                    Label(mood.displayName, systemImage: mood.icon)
                        .font(OffRecordWidgetTypography.label)
                        .foregroundStyle(mood.readableColor)
                        .widgetAccentable()
                } else if let line = todayMetadataLine(for: entry) {
                    Text(line)
                        .font(OffRecordWidgetTypography.metadata)
                        .foregroundStyle(OffRecordColor.textSecondary)
                }

                Spacer(minLength: 0)

                HStack(spacing: 10) {
                    StreakBadge(streak: entry.streak)
                    WeekDots(days: entry.lastSevenDays)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            RecordIntentButton {
                VStack(spacing: 6) {
                    RecordGlyph(diameter: 56)
                    Text(entry.hasEntryToday ? "Add More" : "Record")
                        .font(OffRecordWidgetTypography.label)
                        .foregroundStyle(OffRecordColor.textHeading)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var headline: String {
        if entry.hasEntryToday {
            if let line = todayMetadataLine(for: entry), entry.todayMood != nil {
                return String(localized: "Journaled · \(line)")
            }
            return String(localized: "Journaled today")
        }
        return String(localized: "What’s on your mind?")
    }
}

struct WeekDots: View {
    let days: [WidgetDay]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(days, id: \.self) { day in
                Circle()
                    .fill(day.mood?.color ?? (day.hasEntry ? OffRecordColor.pixelNeutral : OffRecordColor.pixelEmpty))
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(days.filter(\.hasEntry).count) of the last 7 days journaled")
    }
}

struct TodayCircularView: View {
    let entry: JournalWidgetEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 1) {
                Image(systemName: entry.hasEntryToday ? "checkmark" : "mic.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .widgetAccentable()
                Text("\(entry.streak)")
                    .font(OffRecordWidgetTypography.micro.monospacedDigit())
            }
        }
        .accessibilityLabel(entry.hasEntryToday ? "Journaled today, \(entry.streak)-day streak" : "Record today’s entry")
    }
}

struct TodayRectangularView: View {
    let entry: JournalWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label("OffRecord", systemImage: "mic.fill")
                .font(OffRecordWidgetTypography.label)
                .widgetAccentable()
            Text(entry.hasEntryToday ? "Journaled today" : "Not yet today")
                .font(OffRecordWidgetTypography.cardTitle)
                .lineLimit(1)
            Text("\(entry.streak)-day streak")
                .font(OffRecordWidgetTypography.metadata)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TodayInlineView: View {
    let entry: JournalWidgetEntry

    var body: some View {
        if entry.hasEntryToday {
            Label("Journaled · \(entry.streak)-day streak", systemImage: "checkmark.circle")
        } else {
            Label("Record today’s entry", systemImage: "mic")
        }
    }
}

struct OffRecordWidget: Widget {
    let kind: String = "OffRecordWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: JournalSnapshotProvider()) { entry in
            TodayWidgetView(entry: entry)
                .offRecordWidgetBackground()
                .widgetURL(entry.hasEntryToday ? OffRecordWidgetRoute.today : OffRecordWidgetRoute.record)
        }
        .configurationDisplayName("Today")
        .description("See if you’ve journaled today and start a recording.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Streak widget

struct StreakWidgetView: View {
    let entry: JournalWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .widgetAccentable()
                    Text("\(entry.streak)")
                        .font(OffRecordWidgetTypography.numberSmall)
                        .minimumScaleFactor(0.6)
                }
            }
            .accessibilityLabel("\(entry.streak)-day streak")
        case .accessoryInline:
            Label("\(entry.streak)-day streak", systemImage: "flame")
        default:
            SmallStreakView(entry: entry)
        }
    }
}

struct SmallStreakView: View {
    let entry: JournalWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                ZStack {
                    Circle().fill(streakColor.opacity(0.28))
                    Image(systemName: "flame.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(OffRecordColor.textWarm)
                }
                .frame(width: 36, height: 36)
                .widgetAccentable()
                Spacer()
            }

            Spacer(minLength: 0)

            Text("\(entry.streak)")
                .font(OffRecordWidgetTypography.numberLarge)
                .foregroundStyle(OffRecordColor.textHeading)
                .contentTransition(.numericText())
            Text("day streak")
                .font(OffRecordWidgetTypography.metadata)
                .foregroundStyle(OffRecordColor.textSecondary)

            Spacer(minLength: 0)

            WeekDots(days: entry.lastSevenDays)
            Text(entry.hasEntryToday ? "Done today" : "Not yet today")
                .font(OffRecordWidgetTypography.micro)
                .foregroundStyle(entry.hasEntryToday ? OffRecordColor.textSage : OffRecordColor.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var streakColor: Color {
        if entry.streak >= 30 { return OffRecordColor.brandPeach }
        if entry.streak >= 7 { return OffRecordColor.brandYellow }
        return OffRecordColor.brandCoral
    }
}

struct StreakWidget: Widget {
    let kind: String = "StreakWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: JournalSnapshotProvider()) { entry in
            StreakWidgetView(entry: entry)
                .offRecordWidgetBackground()
                .widgetURL(entry.hasEntryToday ? OffRecordWidgetRoute.timeline : OffRecordWidgetRoute.record)
        }
        .configurationDisplayName("Streak")
        .description("See how many days in a row you’ve journaled.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryInline])
    }
}

// MARK: - Quick Record widget

struct QuickRecordWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "mic.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .widgetAccentable()
            }
            .accessibilityLabel("Record")
        default:
            RecordIntentButton {
                VStack(alignment: .leading, spacing: 6) {
                    RecordGlyph(diameter: 54)
                    Spacer(minLength: 0)
                    Text("Record")
                        .font(OffRecordWidgetTypography.titleSmall)
                        .foregroundStyle(OffRecordColor.textHeading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
    }
}

struct QuickRecordWidget: Widget {
    let kind: String = "QuickRecordWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: JournalSnapshotProvider()) { _ in
            QuickRecordWidgetView()
                .offRecordWidgetBackground()
                .widgetURL(OffRecordWidgetRoute.record)
        }
        .configurationDisplayName("Quick Record")
        .description("Start a recording in one tap.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

// MARK: - Widget Bundle

@main
struct OffRecordWidgetBundle: WidgetBundle {
    var body: some Widget {
        OffRecordWidget()
        StreakWidget()
        MoodWidget()
        QuickRecordWidget()
        YearInPixelsWidget()
        RecordEntryControl()
        CaptureLiveActivityWidget()
    }
}

// MARK: - Previews

#Preview("Today - Small", as: .systemSmall) {
    OffRecordWidget()
} timeline: {
    JournalWidgetEntry.sample
    JournalWidgetEntry(date: Date(), snapshot: .empty)
}

#Preview("Today - Medium", as: .systemMedium) {
    OffRecordWidget()
} timeline: {
    JournalWidgetEntry.sample
    JournalWidgetEntry(date: Date(), snapshot: .empty)
}

#Preview("Today - Rectangular", as: .accessoryRectangular) {
    OffRecordWidget()
} timeline: {
    JournalWidgetEntry.sample
}

#Preview("Streak", as: .systemSmall) {
    StreakWidget()
} timeline: {
    JournalWidgetEntry.sample
}

#Preview("Quick Record", as: .systemSmall) {
    QuickRecordWidget()
} timeline: {
    JournalWidgetEntry.sample
}
