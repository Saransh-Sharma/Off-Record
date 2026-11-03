//
//  EntryDetailView+DaySummary.swift
//  OffRecord
//
//  The day summary card: the full date, when it was last updated, and the
//  chips for mood, journal, words, recording length, photos, and a recording
//  that lives on another device.
//

import SwiftUI

extension EntryDetailView {
    var daySummaryCard: some View {
        VStack(alignment: .leading, spacing: OffRecordSpacing.md) {
            HStack(alignment: .center, spacing: OffRecordSpacing.md) {
                OffRecordIconBubble(
                    systemImage: "calendar",
                    tint: selectedMood == .none ? OffRecordColor.textBrand : selectedMood.readableStyle.foreground,
                    fill: selectedMood == .none ? OffRecordColor.surfaceLavender : selectedMood.readableStyle.fill,
                    size: 42,
                    iconSize: 16
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(formattedFullDate)
                        .font(OffRecordTypography.labelLarge)
                        .foregroundStyle(OffRecordColor.textHeading)
                        .fixedSize(horizontal: false, vertical: true)

                    if let updatedAt = entry.updatedAt {
                        Text("Updated \(formattedTime(updatedAt))")
                            .font(OffRecordTypography.metadata)
                            .foregroundStyle(OffRecordColor.textSecondary)
                    }
                }
                Spacer(minLength: 0)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: OffRecordSpacing.sm) {
                    moodHeaderButton

                    EntryJournalMenu(entry: entry)

                    metadataChip(
                        systemImage: "text.word.spacing",
                        text: String(AttributedString(localized: "^[\(activeWordCount) word](inflect: true)").characters)
                    )

                    if let duration = entry.value(forKey: "duration") as? Double, duration > 0 {
                        metadataChip(systemImage: "waveform", text: formattedDuration(duration))
                    }

                    if !photoAttachments.isEmpty {
                        metadataChip(
                            systemImage: "photo",
                            text: String(AttributedString(localized: "^[\(photoAttachments.count) photo](inflect: true)").characters)
                        )
                    }

                    if audioOnOtherDevice {
                        metadataChip(systemImage: "icloud", text: String(localized: "Recording on another device"))
                    }
                }
                .padding(.vertical, 1)
            }
        }
        .padding(OffRecordSpacing.lg)
        .background(OffRecordColor.surfaceWarm, in: RoundedRectangle(cornerRadius: OffRecordRadius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: OffRecordRadius.xl, style: .continuous)
                .stroke(OffRecordColor.borderSoft, lineWidth: 1)
        )
        .offRecordShadow(.card)
    }

    private var moodHeaderButton: some View {
        Button(action: { showMoodPicker = true }) {
            HStack(spacing: OffRecordSpacing.xs) {
                if selectedMood == .none {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Mood")
                } else {
                    selectedMood.miniImage
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                    Text(selectedMood.displayName)
                }
            }
            .font(OffRecordTypography.labelSmall)
            .foregroundStyle(selectedMood == .none ? OffRecordReadableTintStyle.journal.foreground : selectedMood.readableStyle.foreground)
            .padding(.horizontal, OffRecordSpacing.md)
            .frame(minHeight: OffRecordLayout.minimumTapTarget)
            .background(selectedMood == .none ? OffRecordReadableTintStyle.journal.fill : selectedMood.readableStyle.fill, in: Capsule())
            .overlay(Capsule().stroke(selectedMood == .none ? OffRecordReadableTintStyle.journal.border : selectedMood.readableStyle.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(selectedMood == .none ? "Add Mood" : "Mood, \(selectedMood.displayName)")
        .accessibilityHint("Opens the mood dial.")
        .accessibilityIdentifier("entryDetail.moodButton")
    }

    private func metadataChip(systemImage: String, text: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(OffRecordTypography.metadata)
            .foregroundStyle(OffRecordColor.textSecondary)
            .padding(.horizontal, OffRecordSpacing.md)
            .frame(minHeight: 32)
            .background(OffRecordColor.surfacePrimary.opacity(0.68), in: Capsule())
            .overlay(Capsule().stroke(OffRecordColor.borderSoft, lineWidth: 1))
    }

    private var formattedFullDate: String {
        EntryDetailDateFormatters.fullDate.string(from: entry.date ?? Date())
    }

    private func formattedTime(_ date: Date) -> String {
        EntryDetailDateFormatters.time.string(from: date)
    }

    private func formattedDuration(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        if minutes > 0 {
            return String(localized: "\(minutes)m \(seconds)s", comment: "Short recording length in minutes and seconds.")
        }
        return String(localized: "\(seconds)s", comment: "Short recording length in seconds.")
    }

    /// Entry has an audio filename stored (may have been recorded on another device)
    var hasAudioReference: Bool {
        !audioURLs().isEmpty
    }

    /// Audio file exists locally on this device
    private var hasAudio: Bool {
        audioURLs().contains { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Audio was recorded but file is on another device (synced via iCloud)
    private var audioOnOtherDevice: Bool {
        hasAudioReference && !hasAudio
    }

    private func audioURL() -> URL? {
        audioURLs().first
    }

    private func audioURLs() -> [URL] {
        AudioAttachmentStore.audioURLs(for: entry)
    }
}
