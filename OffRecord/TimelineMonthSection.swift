//
//  TimelineMonthSection.swift
//  OffRecord
//

import CoreData
import SwiftUI

struct TimelineEntryPresentation: Equatable {
    let wordCount: Int
    let hasPhotos: Bool

    static let empty = TimelineEntryPresentation(wordCount: 0, hasPhotos: false)
}

struct CalendarSectionIcon: View {
    var body: some View {
        ZStack {
            Image(systemName: "calendar")
                .font(OffRecordTypography.titleMedium)
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
    let metrics: TimelineEntryPresentation?
    let searchText: String
    let evidence: EvidenceReference?
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: TimelineDesign.dayRowContentSpacing) {
            TimelineDateSpine(date: entry.date ?? Date(), index: index, isLast: isLast)
                .frame(width: TimelineDesign.daySpineWidth)

            Button(action: onSelect) {
                TimelineEntryCard(
                    entry: entry,
                    metrics: metrics,
                    searchText: searchText,
                    evidence: evidence
                )
                .overlay(selectionOverlay)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier(entryAccessibilityIdentifier)
            .accessibilityHint("Opens the entry. Swipe for star and delete.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var entryAccessibilityIdentifier: String {
        let id = entry.id?.uuidString ?? entry.objectID.uriRepresentation().absoluteString
        return "timeline.entryRow.\(id)"
    }

    @ViewBuilder
    private var selectionOverlay: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: OffRecordRadius.lg, style: .continuous)
                .stroke(OffRecordColor.textLavender.opacity(0.72), lineWidth: 2)
                .padding(1)
                .accessibilityHidden(true)
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
                    .font(OffRecordTypography.numberSmall)
                    .foregroundStyle(style.foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(weekday)
                    .font(OffRecordTypography.badgeLabel)
                    .foregroundStyle(style.foreground)
                    .lineLimit(1)
            }
            .frame(width: TimelineDesign.dateBadgeSize, height: TimelineDesign.dateBadgeSize)
            .background(Circle().fill(style.fill))
            .overlay(Circle().stroke(style.border, lineWidth: 1.1))
            .padding(.top, TimelineDesign.dateBadgeTopPadding)
        }
        .frame(minHeight: TimelineDesign.dateBadgeSize + TimelineDesign.dateBadgeTopPadding * 2)
        .accessibilityHidden(true)
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
