//
//  TimelineLenses.swift
//  OffRecord
//
//  Alternate ways to look back: a mood calendar (month and year-in-pixels)
//  and a media grid of every photo in the journal.
//

import CoreData
import SwiftUI

enum TimelineLens: String, CaseIterable, Identifiable {
    case list = "List"
    case calendar = "Calendar"
    case media = "Media"

    var id: String { rawValue }

    /// The segment label. The raw value stays fixed because it is the identity.
    var displayName: String {
        switch self {
        case .list: return String(localized: "List", comment: "Timeline view option: entries as a list.")
        case .calendar: return String(localized: "Calendar", comment: "Timeline view option: entries on a mood calendar.")
        case .media: return String(localized: "Photos", comment: "Timeline view option: a grid of every photo.")
        }
    }

    var systemImage: String {
        switch self {
        case .list: return "list.bullet"
        case .calendar: return "calendar"
        case .media: return "photo.on.rectangle"
        }
    }
}

// MARK: - Calendar

struct TimelineCalendarView: View {
    let entries: [DiaryEntry]
    let onSelect: (DiaryEntry) -> Void

    enum Scale: String, CaseIterable, Identifiable {
        case month = "Month"
        case year = "Year"
        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .month: return String(localized: "Month", comment: "Calendar scale showing one month")
            case .year: return String(localized: "Year", comment: "Calendar scale showing the whole year")
            }
        }
    }

    @State private var displayedMonth = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
    @State private var scale: Scale = .month
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let calendar = Calendar.current

    /// One entry per day (the daily store keeps a single entry per day).
    private var entriesByDay: [Date: DiaryEntry] {
        var result: [Date: DiaryEntry] = [:]
        for entry in entries {
            guard let date = entry.date else { continue }
            let day = calendar.startOfDay(for: date)
            if result[day] == nil { result[day] = entry }
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OffRecordSpacing.lg) {
            header

            Group {
                switch scale {
                case .month:
                    monthGrid(for: displayedMonth, cellStyle: .full)
                        .id(displayedMonth)
                        .transition(.opacity)
                case .year:
                    yearGrid
                        .transition(.opacity)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 30).onEnded { value in
                    guard scale == .month, abs(value.translation.width) > abs(value.translation.height) else { return }
                    shiftMonth(by: value.translation.width < 0 ? 1 : -1)
                }
            )
            .simultaneousGesture(
                MagnifyGesture().onEnded { value in
                    withOffRecordAnimation(OffRecordMotion.gentle) {
                        scale = value.magnification < 0.85 ? .year : (value.magnification > 1.15 ? .month : scale)
                    }
                }
            )

            summary
        }
        .padding(OffRecordSpacing.xl)
        .offRecordCard(fill: OffRecordColor.surfacePrimary)
        .offRecordAnimation(OffRecordMotion.gentle, value: scale)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("timeline.calendar")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: OffRecordSpacing.sm) {
            HStack(spacing: OffRecordSpacing.xs) {
                ViewThatFits(in: .horizontal) {
                    titleText(scale == .month ? displayedMonth.formatted(.dateTime.month(.wide).year()) : displayedMonth.formatted(.dateTime.year()))
                    titleText(scale == .month ? displayedMonth.formatted(.dateTime.month(.abbreviated).year()) : displayedMonth.formatted(.dateTime.year()))
                }
                .layoutPriority(1)

                Spacer(minLength: 0)

                if scale == .month {
                    Button { shiftMonth(by: -1) } label: {
                        Image(systemName: "chevron.left")
                            .frame(width: OffRecordLayout.minimumTapTarget, height: OffRecordLayout.minimumTapTarget)
                    }
                    .accessibilityLabel("Previous Month")

                    Button { shiftMonth(by: 1) } label: {
                        Image(systemName: "chevron.right")
                            .frame(width: OffRecordLayout.minimumTapTarget, height: OffRecordLayout.minimumTapTarget)
                    }
                    .disabled(isShowingCurrentMonth)
                    .accessibilityLabel("Next Month")
                }
            }
            .font(OffRecordTypography.labelLarge)
            .foregroundStyle(OffRecordColor.textBrand)

            Picker("Calendar Scale", selection: $scale) {
                ForEach(Scale.allCases) { scale in
                    Text(scale.displayName).tag(scale)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func titleText(_ text: String) -> some View {
        Text(text)
            .font(OffRecordTypography.titleSmall)
            .foregroundStyle(OffRecordColor.textHeading)
            .lineLimit(1)
            .contentTransition(.numericText())
            .accessibilityAddTraits(.isHeader)
    }

    private var isShowingCurrentMonth: Bool {
        calendar.isDate(displayedMonth, equalTo: Date(), toGranularity: .month)
    }

    private func shiftMonth(by value: Int) {
        guard let next = calendar.date(byAdding: .month, value: value, to: displayedMonth) else { return }
        guard next <= Date() else { return }
        withOffRecordAnimation(OffRecordMotion.snappy) {
            displayedMonth = next
        }
    }

    enum CellStyle {
        case full
        case pixel
    }

    private func days(in month: Date) -> [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let dayCount = calendar.range(of: .day, in: .month, for: month)?.count else { return [] }
        let firstWeekday = calendar.component(.weekday, from: interval.start)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7
        var result: [Date?] = Array(repeating: nil, count: leading)
        for offset in 0..<dayCount {
            result.append(calendar.date(byAdding: .day, value: offset, to: interval.start))
        }
        return result
    }

    @ViewBuilder
    private func monthGrid(for month: Date, cellStyle: CellStyle) -> some View {
        let spacing: CGFloat = cellStyle == .full ? 6 : 2
        let allDays = days(in: month)
        let weeks = stride(from: 0, to: allDays.count, by: 7).map { start in
            Array(allDays[start..<min(start + 7, allDays.count)]) + Array(repeating: nil, count: max(0, start + 7 - allDays.count))
        }
        Grid(horizontalSpacing: spacing, verticalSpacing: spacing) {
            if cellStyle == .full {
                GridRow {
                    ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                        Text(symbol)
                            .font(OffRecordTypography.annotation)
                            .foregroundStyle(OffRecordColor.textTertiary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .accessibilityHidden(true)
            }
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                GridRow {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        if let day {
                            dayCell(day, style: cellStyle)
                        } else {
                            Color.clear
                                .aspectRatio(1, contentMode: .fit)
                                .frame(maxWidth: .infinity)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
        }
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
    }

    @ViewBuilder
    private func dayCell(_ day: Date, style: CellStyle) -> some View {
        let entry = entriesByDay[calendar.startOfDay(for: day)]
        let mood = entry.flatMap { Mood(rawValue: $0.mood ?? "") } ?? .none
        let isToday = calendar.isDateInToday(day)
        let fill: Color = entry == nil
            ? OffRecordColor.textTertiary.opacity(style == .full ? 0.08 : 0.14)
            : (mood == .none ? OffRecordColor.brandLavender.opacity(0.55) : mood.color)

        switch style {
        case .full:
            Button {
                if let entry { onSelect(entry) }
            } label: {
                RoundedRectangle(cornerRadius: OffRecordRadius.xs, style: .continuous)
                    .fill(fill)
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .overlay {
                        Text(day.formatted(.dateTime.day()))
                            .font(OffRecordTypography.labelSmall)
                            .foregroundStyle(entry == nil ? OffRecordColor.textTertiary : Color(hex: 0x241730))
                            .minimumScaleFactor(0.6)
                    }
                    .overlay {
                        if isToday {
                            RoundedRectangle(cornerRadius: OffRecordRadius.xs, style: .continuous)
                                .stroke(OffRecordColor.textBrand, lineWidth: 1.5)
                        }
                    }
            }
            .buttonStyle(.plain)
            .disabled(entry == nil)
            .accessibilityLabel(dayAccessibilityLabel(day, entry: entry, mood: mood))
        case .pixel:
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(fill)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
        }
    }

    private func dayAccessibilityLabel(_ day: Date, entry: DiaryEntry?, mood: Mood) -> String {
        let date = day.formatted(.dateTime.weekday(.wide).month(.wide).day())
        guard entry != nil else { return String(localized: "\(date), no entry", comment: "VoiceOver label for a calendar day with no entry. The argument is the date.") }
        return mood == .none
            ? String(localized: "\(date), entry", comment: "VoiceOver label for a calendar day with an entry. The argument is the date.")
            : String(localized: "\(date), \(mood.displayName) entry", comment: "VoiceOver label for a calendar day with an entry. The arguments are the date and the mood.")
    }

    private var yearGrid: some View {
        let year = calendar.component(.year, from: displayedMonth)
        let months: [Date] = (1...12).compactMap { month in
            calendar.date(from: DateComponents(year: year, month: month, day: 1))
        }
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: OffRecordSpacing.md), count: 3), spacing: OffRecordSpacing.md) {
            ForEach(months, id: \.self) { month in
                Button {
                    displayedMonth = month
                    withOffRecordAnimation(OffRecordMotion.gentle) { scale = .month }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(month.formatted(.dateTime.month(.abbreviated)))
                            .font(OffRecordTypography.annotation.weight(.semibold))
                            .foregroundStyle(OffRecordColor.textSecondary)
                        monthGrid(for: month, cellStyle: .pixel)
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                }
                .buttonStyle(.plain)
                .disabled(month > Date())
                .opacity(month > Date() ? 0.4 : 1)
                .accessibilityLabel(String(AttributedString(localized: "\(month.formatted(.dateTime.month(.wide))), ^[\(journaledDays(in: month)) day](inflect: true) journaled").characters))
            }
        }
    }

    private func journaledDays(in month: Date) -> Int {
        entriesByDay.keys.filter { calendar.isDate($0, equalTo: month, toGranularity: .month) }.count
    }

    private var summary: some View {
        let range: Calendar.Component = scale == .month ? .month : .year
        let inRange = entriesByDay.filter { calendar.isDate($0.key, equalTo: displayedMonth, toGranularity: range) }
        let moods = inRange.values.compactMap { Mood(rawValue: $0.mood ?? "") }.filter { $0 != .none }
        let common = Dictionary(grouping: moods, by: { $0 }).max { $0.value.count < $1.value.count }?.key
        let period = scale == .month ? displayedMonth.formatted(.dateTime.month(.wide)) : displayedMonth.formatted(.dateTime.year())
        var text = String(AttributedString(localized: "^[\(inRange.count) day](inflect: true) in \(period)").characters)
        if let common { text = String(localized: "\(text) · mostly \(common.displayName.lowercased())", comment: "Calendar summary. The first argument is like “12 days in September”; the second is the most common mood.") }
        return Text(text)
            .font(OffRecordTypography.metadata)
            .foregroundStyle(OffRecordColor.textSecondary)
    }
}

// MARK: - Media

struct TimelineMediaGrid: View {
    let entries: [DiaryEntry]
    let onSelect: (DiaryEntry) -> Void

    private struct Item: Identifiable {
        let id: NSManagedObjectID
        let entry: DiaryEntry
        let attachment: PhotoAttachment
    }

    private var items: [Item] {
        entries.flatMap { entry in
            PhotoStorageManager.shared.attachments(for: entry).map {
                Item(id: $0.objectID, entry: entry, attachment: $0)
            }
        }
    }

    var body: some View {
        let items = items
        if items.isEmpty {
            TimelineLensEmptyState(
                systemImage: "photo.on.rectangle.angled",
                title: String(localized: "No Photos"),
                message: String(localized: "Photos you add to entries show up here.")
            )
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 4)], spacing: 4) {
                ForEach(items) { item in
                    Button {
                        onSelect(item.entry)
                    } label: {
                        TimelinePhotoThumbnail(attachment: item.attachment)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Photo from \((item.entry.date ?? Date()).formatted(date: .long, time: .omitted))")
                    .accessibilityHint("Opens the entry.")
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: OffRecordRadius.lg, style: .continuous))
            .accessibilityIdentifier("timeline.mediaGrid")
        }
    }
}

private struct TimelinePhotoThumbnail: View {
    let attachment: PhotoAttachment
    @State private var image: UIImage?

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                } else {
                    OffRecordColor.surfaceLavender
                }
            }
            .clipped()
            .task(id: attachment.objectID) {
                guard image == nil, let data = attachment.imageData else { return }
                let thumbnail = await Task.detached(priority: .userInitiated) {
                    PhotoStorageManager.thumbnailImage(from: data, maxPixelDimension: 320)
                }.value
                withOffRecordAnimation(OffRecordMotion.fade) { image = thumbnail }
            }
    }
}

struct TimelineLensEmptyState: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: OffRecordSpacing.md) {
            Image(systemName: systemImage)
                .font(OffRecordTypography.titleLarge)
                .foregroundStyle(OffRecordColor.textLavender)
                .accessibilityHidden(true)
            Text(title)
                .font(OffRecordTypography.sectionTitle)
                .foregroundStyle(OffRecordColor.textHeading)
            Text(message)
                .font(OffRecordTypography.bodySmall)
                .foregroundStyle(OffRecordColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, OffRecordSpacing.section)
        .padding(.horizontal, OffRecordSpacing.xl)
        .offRecordCard(fill: OffRecordColor.surfacePrimary.opacity(0.8), shadow: false)
    }
}
