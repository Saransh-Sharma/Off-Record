//
//  EntryDetailView+BlockRows.swift
//  OffRecord
//
//  One row per journal block: text (read or edited in place), a recording
//  or the note that it was recorded elsewhere, a mood, or a photo, plus the
//  shared row header and its More menu.
//

import SwiftUI

extension EntryDetailView {
    @ViewBuilder
    func journalBlockRow(_ item: JournalBlockTimelineItem) -> some View {
        switch item.kind {
        case .text:
            textBlockRow(item)
        case .audio:
            audioBlockRow(item)
        case .mood:
            moodBlockRow(item)
        case .photo:
            photoBlockRow(item)
        }
    }

    private func textBlockRow(_ item: JournalBlockTimelineItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            blockHeader(item: item, systemImage: "text.alignleft", canEdit: true)
            textBlockBody(item)
        }
        .padding(14)
        .background(OffRecordColor.surfacePrimary.opacity(0.92), in: RoundedRectangle(cornerRadius: OffRecordRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: OffRecordRadius.lg, style: .continuous)
                .stroke(OffRecordColor.borderSoft, lineWidth: 1)
        )
        .shadow(color: OffRecordShadow.cardColor, radius: 10, x: 0, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.accessibilityLabel)
    }

    @ViewBuilder
    func textBlockBody(_ item: JournalBlockTimelineItem) -> some View {
        if editingBlockObjectID == item.id {
            TextEditor(text: $editingBlockText)
                .font(OffRecordTypography.journalBody)
                .foregroundColor(OffRecordColor.textPrimary)
                .lineSpacing(6)
                .focused($isTextFocused)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 220)
                .padding(14)
                .background(OffRecordColor.surfaceWarm, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(blockEditError == nil ? OffRecordColor.borderWarm : OffRecordColor.brandCoral.opacity(0.42), lineWidth: 1)
                )

            if let blockEditError {
                Text(blockEditError)
                    .font(OffRecordTypography.metadata)
                    .foregroundColor(OffRecordColor.brandCoral)
            }
        } else {
            Text(item.text)
                .font(OffRecordTypography.journalBody)
                .foregroundColor(OffRecordColor.textPrimary)
                .lineSpacing(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .accessibilityIdentifier("entryDetail.mainText")
                .onTapGesture {
                    beginEditingBlock(item)
                }
        }
    }

    private func audioBlockRow(_ item: JournalBlockTimelineItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            blockHeader(item: item, systemImage: "waveform", accent: OffRecordColor.textSky)
            audioBlockBody(item)
        }
        .padding(14)
        .offRecordContentCard(cornerRadius: 18, fill: OffRecordColor.surfaceBlue)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.accessibilityLabel)
        .accessibilityValue(item.recordingElsewhereAccessibilityValue)
    }

    @ViewBuilder
    func audioBlockBody(_ item: JournalBlockTimelineItem) -> some View {
        if let url = item.audioURL, item.audioExists {
            AudioPlayerView(audioURL: url)
        } else {
            RecordingElsewhereNote(
                origin: item.recordingElsewhereOrigin ?? .anotherDevice,
                duration: item.duration
            )
        }
    }

    private func moodBlockRow(_ item: JournalBlockTimelineItem) -> some View {
        HStack(spacing: 12) {
            MiniMoodIcon(mood: item.mood, size: 26, opacity: 0.94)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.timestamp)
                    .font(OffRecordTypography.metadata)
                    .foregroundColor(OffRecordColor.textSecondary)
                Text(item.mood.displayName)
                    .font(OffRecordTypography.labelMedium)
                    .foregroundColor(OffRecordColor.textPrimary)
            }
            Spacer()
            blockOverflowMenu(item, canEdit: false)
        }
        .padding(14)
        .offRecordContentCard(cornerRadius: 18, fill: item.mood.readableStyle.fill)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.accessibilityLabel)
    }

    @ViewBuilder
    private func photoBlockRow(_ item: JournalBlockTimelineItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            blockHeader(item: item, systemImage: "photo", accent: OffRecordColor.textPeach)
            photoBlockBody(item)
        }
        .padding(14)
        .offRecordContentCard(cornerRadius: 18, fill: OffRecordColor.surfacePeach)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.accessibilityLabel)
    }

    @ViewBuilder
    func photoBlockBody(_ item: JournalBlockTimelineItem) -> some View {
        #if canImport(UIKit)
        if let id = item.photoAttachmentID,
           let image = photoThumbnailByID[id] {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            Label("Photo", systemImage: "photo")
                .font(OffRecordTypography.metadata)
                .foregroundStyle(OffRecordColor.textSecondary)
        }
        #else
        Label("Photo", systemImage: "photo")
            .font(OffRecordTypography.metadata)
            .foregroundStyle(OffRecordColor.textSecondary)
        #endif
    }

    func blockHeader(
        item: JournalBlockTimelineItem,
        systemImage: String,
        canEdit: Bool = false,
        accent: Color = OffRecordColor.textSecondary
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(accent)
            Text(item.timestamp)
            Spacer()
            blockOverflowMenu(item, canEdit: canEdit)
        }
        .font(OffRecordTypography.metadata)
        .foregroundColor(OffRecordColor.textSecondary)
    }

    private func blockOverflowMenu(_ item: JournalBlockTimelineItem, canEdit: Bool) -> some View {
        Menu {
            if canEdit {
                Button {
                    beginEditingBlock(item)
                } label: {
                    Label(String(localized: "Edit", comment: "Menu action that edits a text block."), systemImage: "pencil")
                }
            }
            Button(role: .destructive) {
                deleteBlock(item)
            } label: {
                Label(String(localized: "Delete", comment: "Menu action that deletes a block from the entry."), systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(OffRecordTypography.labelSmall)
                .foregroundColor(OffRecordColor.textSecondary)
        }
        .accessibilityLabel(Text("More", comment: "Accessibility label for the menu with more actions for this block."))
    }
}
