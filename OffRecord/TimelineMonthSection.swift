//
//  TimelineMonthSection.swift
//  OffRecord
//

import SwiftUI

struct TimelineMonthSection: View {
    let title: String
    let entries: [DiaryEntry]
    let searchText: String
    let semanticResults: [UUID: EvidenceReference]
    let isEditing: Bool
    let onDelete: (DiaryEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                CalendarSectionIcon()

                Text(title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(OffRecordColor.textBrand)

                Spacer()

                Text("\(entries.count) \(entries.count == 1 ? "entry" : "entries")")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(OffRecordColor.textBrand.opacity(0.75))
            }
            .padding(.horizontal, 2)

            LazyVStack(spacing: TimelineDesign.monthRowSpacing) {
                ForEach(Array(entries.enumerated()), id: \.element.objectID) { index, entry in
                    TimelineDayRow(
                        entry: entry,
                        index: index,
                        isLast: index == entries.count - 1,
                        searchText: searchText,
                        evidence: entry.id.flatMap { semanticResults[$0] },
                        isEditing: isEditing,
                        onDelete: { onDelete(entry) }
                    )
                }
            }
        }
    }
}

struct CalendarSectionIcon: View {
    var body: some View {
        ZStack {
            Image(systemName: "calendar")
                .font(.system(size: 27, weight: .semibold))
                .foregroundStyle(OffRecordColor.textBrand)
            Circle()
                .fill(OffRecordColor.brandCoral)
                .frame(width: 4, height: 4)
                .offset(x: -6, y: 6)
            Circle()
                .fill(OffRecordColor.brandLavenderDark)
                .frame(width: 4, height: 4)
                .offset(x: 6, y: 6)
        }
        .frame(width: 38, height: 38)
        .accessibilityHidden(true)
    }
}

struct TimelineDayRow: View {
    let entry: DiaryEntry
    let index: Int
    let isLast: Bool
    let searchText: String
    let evidence: EvidenceReference?
    let isEditing: Bool
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: TimelineDesign.dayRowContentSpacing) {
            TimelineDateSpine(date: entry.date ?? Date(), index: index, isLast: isLast)
                .frame(width: TimelineDesign.daySpineWidth)

            NavigationLink {
                EntryDetailView(entry: entry)
            } label: {
                TimelineEntryCard(
                    entry: entry,
                    searchText: searchText,
                    evidence: evidence,
                    isEditing: isEditing,
                    onDelete: onDelete
                )
            }
            .buttonStyle(.plain)
        }
    }
}

struct TimelineDateSpine: View {
    let date: Date
    let index: Int
    let isLast: Bool

    private var style: TimelineDateBadgeStyle {
        TimelineDateBadgeStyle.styles[index % TimelineDateBadgeStyle.styles.count]
    }

    var body: some View {
        ZStack(alignment: .top) {
            if !isLast {
                TimelineSpineLine()
                    .stroke(
                        OffRecordColor.textTertiary.opacity(0.58),
                        style: StrokeStyle(lineWidth: 0.95, dash: [4, 7], dashPhase: 1)
                    )
                    .padding(.top, TimelineDesign.dateBadgeTopPadding + TimelineDesign.dateBadgeSize + 4)
                    .frame(maxHeight: .infinity)
                    .allowsHitTesting(false)
            }

            VStack(spacing: -1) {
                Text(dayNumber)
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(style.foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(weekday)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(style.foreground)
                    .lineLimit(1)
            }
            .frame(width: TimelineDesign.dateBadgeSize, height: TimelineDesign.dateBadgeSize)
            .background(Circle().fill(style.fill))
            .overlay(Circle().stroke(style.border, lineWidth: 1.1))
            .padding(.top, TimelineDesign.dateBadgeTopPadding)
        }
        .frame(minHeight: TimelineDesign.entryRowMinHeight)
    }

    private var dayNumber: String {
        String(Calendar.current.component(.day, from: date))
    }

    private var weekday: String {
        date.formatted(.dateTime.weekday(.abbreviated)).uppercased()
    }
}

struct TimelineSpineLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}

struct TimelineDateBadgeStyle {
    let fill: Color
    let border: Color
    let foreground: Color

    static let styles: [TimelineDateBadgeStyle] = [
        .init(fill: OffRecordColor.surfaceLavender, border: OffRecordColor.brandLavender.opacity(0.42), foreground: OffRecordColor.textBrand),
        .init(fill: OffRecordColor.backgroundPeachTint, border: OffRecordColor.brandPeach.opacity(0.42), foreground: OffRecordColor.textPeach),
        .init(fill: OffRecordColor.backgroundLavenderTint, border: OffRecordColor.brandLavender.opacity(0.36), foreground: OffRecordColor.textBrand),
        .init(fill: OffRecordColor.backgroundSkyTint, border: OffRecordColor.brandSky.opacity(0.48), foreground: OffRecordColor.textSky)
    ]
}
