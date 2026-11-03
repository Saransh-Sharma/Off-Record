//
//  EntryDetailView+Timeline.swift
//  OffRecord
//
//  The entry's blocks laid out as one canvas or as a day timeline, the
//  transcribing and empty states, and each block's context menu.
//

import SwiftUI

extension EntryDetailView {
    // MARK: - Reading View

    private var isTranscribing: Bool {
        entry.shouldShowTranscriptionSpinner(displayText: text)
    }

    private var entryPresentationLayout: JournalEntryPresentationLayout {
        JournalEntryPresentationClassifier.layout(
            for: timelineItems.map(\.presentationBlock)
        )
    }

    var journalTimelineView: some View {
        VStack(alignment: .leading, spacing: OffRecordSpacing.md) {
            if timelineItems.isEmpty {
                if isTranscribing {
                    VStack(spacing: OffRecordSpacing.md) {
                        Image(systemName: "waveform")
                            .font(OffRecordTypography.titleLarge)
                            .foregroundStyle(OffRecordColor.textLavender)
                            .symbolEffect(.variableColor.iterative, isActive: !reduceMotion)
                            .accessibilityHidden(true)
                        Text("Transcribing…")
                            .font(OffRecordTypography.bodySmall)
                            .foregroundColor(OffRecordColor.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, OffRecordSpacing.section)
                    .offRecordContentCard(cornerRadius: OffRecordRadius.lg)
                } else {
                    if !isComposingTextBlock {
                        emptyEntryPrompt
                    }
                }
            } else {
                switch entryPresentationLayout {
                case .singleEntry:
                    sectionLabel(dayName)
                    singleEntryCanvas
                case .multiEntry:
                    sectionLabel(dayName)
                    multiEntryTimeline
                }
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.01) : .easeOut(duration: 0.22), value: timelineItems.map(\.id))
    }

    /// "Today", "Yesterday", the weekday ("Wednesday") within a week, or the date ("Sep 12").
    private var dayName: String {
        let date = entry.date ?? Date()
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return String(localized: "Today") }
        if calendar.isDateInYesterday(date) { return String(localized: "Yesterday") }
        if let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: Date())).day, days < 7 {
            return date.formatted(.dateTime.weekday(.wide))
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(OffRecordTypography.labelSmall)
            .foregroundStyle(OffRecordColor.textSecondary)
            .textCase(.uppercase)
            .tracking(0.6)
            .padding(.horizontal, 2)
            .accessibilityAddTraits(.isHeader)
    }

    private var emptyEntryPrompt: some View {
        VStack(spacing: OffRecordSpacing.md) {
            OffRecordIconBubble(
                systemImage: "square.and.pencil",
                tint: OffRecordColor.textLavender,
                fill: OffRecordColor.surfaceLavender,
                size: 46,
                iconSize: 18
            )
            Text("Nothing Here Yet")
                .font(OffRecordTypography.labelMedium)
                .foregroundStyle(OffRecordColor.textHeading)
            Text("Add text, a photo, or a mood.")
                .font(OffRecordTypography.bodySmall)
                .foregroundStyle(OffRecordColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .background(OffRecordColor.surfaceWarm, in: RoundedRectangle(cornerRadius: OffRecordRadius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: OffRecordRadius.xl, style: .continuous)
                .stroke(OffRecordColor.borderSoft, lineWidth: 1)
        )
        .shadow(color: OffRecordShadow.cardColor, radius: 18, x: 0, y: 8)
    }

    private var singleEntryCanvas: some View {
        VStack(spacing: 0) {
            ForEach(Array(timelineItems.enumerated()), id: \.element.id) { index, item in
                singleEntryRow(item, isLast: index == timelineItems.count - 1)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                    .contextMenu { blockContextMenu(for: item) }
            }
        }
        .padding(14)
        .background(OffRecordColor.surfaceLavender.opacity(0.56), in: RoundedRectangle(cornerRadius: OffRecordRadius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: OffRecordRadius.xl, style: .continuous)
                .stroke(OffRecordColor.brandLavender.opacity(0.28), lineWidth: 1)
        )
        .shadow(color: OffRecordShadow.cardColor, radius: 18, x: 0, y: 8)
    }

    private var multiEntryTimeline: some View {
        LazyVStack(spacing: TimelineDesign.monthRowSpacing) {
            ForEach(Array(timelineItems.enumerated()), id: \.element.id) { index, item in
                HStack(alignment: .top, spacing: TimelineDesign.dayRowContentSpacing) {
                    dayTimelineNode(for: item, isLast: index == timelineItems.count - 1)
                        .frame(width: TimelineDesign.daySpineWidth)

                    journalBlockRow(item)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                        .contextMenu { blockContextMenu(for: item) }
                }
                .frame(minHeight: minHeight(for: item), alignment: .top)
            }
        }
    }

    private func singleEntryRow(_ item: JournalBlockTimelineItem, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: OffRecordSpacing.md) {
            ZStack(alignment: .top) {
                if !isLast {
                    TimelineSpineLine()
                        .stroke(OffRecordColor.brandLavender.opacity(0.44), style: StrokeStyle(lineWidth: 1))
                        .padding(.top, 44)
                        .frame(maxHeight: .infinity)
                }

                timelineIconBubble(for: item, size: 44)
            }
            .frame(width: 46)
            .frame(minHeight: minHeight(for: item))

            singleEntryBlockContent(item)
                .padding(.bottom, isLast ? 0 : OffRecordSpacing.md)
        }
    }

    private func singleEntryBlockContent(_ item: JournalBlockTimelineItem) -> some View {
        VStack(alignment: .leading, spacing: OffRecordSpacing.sm) {
            blockHeader(item: item, systemImage: item.systemImage, canEdit: item.kind == .text, accent: item.accentColor)

            switch item.kind {
            case .text:
                textBlockBody(item)
            case .audio:
                audioBlockBody(item)
                    .padding(12)
                    .background(OffRecordColor.surfaceBlue, in: RoundedRectangle(cornerRadius: OffRecordRadius.lg, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: OffRecordRadius.lg, style: .continuous)
                            .stroke(OffRecordColor.brandSky.opacity(0.28), lineWidth: 1)
                    )
            case .mood:
                HStack(spacing: OffRecordSpacing.sm) {
                    if item.mood != .none {
                        item.mood.miniImage
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                            .accessibilityHidden(true)
                    }
                    Text(item.mood.displayName)
                        .font(OffRecordTypography.labelMedium)
                        .foregroundStyle(OffRecordColor.textPrimary)
                }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(item.mood.readableStyle.fill, in: RoundedRectangle(cornerRadius: OffRecordRadius.lg, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: OffRecordRadius.lg, style: .continuous)
                            .stroke(item.mood.readableStyle.border, lineWidth: 1)
                    )
            case .photo:
                photoBlockBody(item)
            }
        }
    }

    private func dayTimelineNode(for item: JournalBlockTimelineItem, isLast: Bool) -> some View {
        ZStack(alignment: .top) {
            if !isLast {
                TimelineSpineLine()
                    .stroke(
                        OffRecordColor.textTertiary.opacity(0.58),
                        style: StrokeStyle(lineWidth: 0.95, dash: [4, 7], dashPhase: 1)
                    )
                    .padding(.top, 52)
                    .frame(maxHeight: .infinity)
                    .allowsHitTesting(false)
            }

            Text(item.timeText)
                .font(OffRecordTypography.badgeLabel)
                .foregroundStyle(item.nodeForeground)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .frame(width: 50, height: 50)
                .background(Circle().fill(item.nodeFill))
                .overlay(Circle().stroke(item.nodeBorder, lineWidth: 1.1))
                .accessibilityLabel("\(item.timeText), \(item.accessibilityLabel)")
        }
        .frame(minHeight: minHeight(for: item))
    }

    private func timelineIconBubble(for item: JournalBlockTimelineItem, size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(item.nodeFill)
                .overlay(Circle().stroke(item.nodeBorder, lineWidth: 1))
            Image(systemName: item.systemImage)
                .font(size == 44 ? OffRecordTypography.labelLarge : OffRecordTypography.labelMedium)
                .foregroundStyle(item.nodeForeground)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func blockContextMenu(for item: JournalBlockTimelineItem) -> some View {
        if item.kind == .text {
            Button {
                beginEditingBlock(item)
            } label: {
                Label(String(localized: "Edit", comment: "Menu action that edits a text block."), systemImage: "pencil")
            }
        }
        if item.kind == .text, let text = block(for: item)?.textValue, !text.isEmpty {
            Button {
                UIPasteboard.general.string = text
            } label: {
                Label("Copy Text", systemImage: "doc.on.doc")
            }
        }
        Button(role: .destructive) {
            pendingBlockDeletion = item
        } label: {
            Label(String(localized: "Delete", comment: "Menu action that deletes a block from the entry."), systemImage: "trash")
        }
    }

    private func minHeight(for item: JournalBlockTimelineItem) -> CGFloat {
        switch item.kind {
        case .text:
            return max(TimelineDesign.entryRowMinHeight, editingBlockObjectID == item.id ? 300 : 112)
        case .audio:
            return 132
        case .mood:
            return 82
        case .photo:
            return 150
        }
    }
}
