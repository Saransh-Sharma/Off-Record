//
//  TimelineEntryCard.swift
//  OffRecord
//

import SwiftUI

struct TimelineEntryCard: View {
    let entry: DiaryEntry
    let metrics: TimelineEntryPresentation?
    let searchText: String
    let evidence: EvidenceReference?
    let isEditing: Bool
    let onDelete: () -> Void

    private var mood: Mood {
        guard let moodString = entry.value(forKey: "mood") as? String,
              let mood = Mood(rawValue: moodString) else {
            return .none
        }
        return mood
    }

    private var wordCount: Int {
        metrics?.wordCount ?? TimelineEntryMetrics.wordCount(for: entry)
    }

    private var hasPhotos: Bool {
        metrics?.hasPhotos ?? !PhotoStorageManager.shared.attachments(for: entry).isEmpty
    }

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    MiniMoodIcon(
                        mood: mood,
                        size: 18,
                        opacity: mood == .none ? 0.5 : 0.82,
                        accessibilityLabel: "\(mood.displayName) mood"
                    )

                    Text("\(wordCount) words")
                        .font(OffRecordTypography.metadata)
                        .foregroundStyle(OffRecordColor.textBrand.opacity(0.76))
                        .lineLimit(1)

                    if hasPhotos {
                        Image(systemName: "photo")
                            .font(OffRecordTypography.annotation)
                            .foregroundStyle(OffRecordColor.textSecondary)
                    }

                    if entry.isStarred {
                        Image(systemName: "star.fill")
                            .font(OffRecordTypography.annotation)
                            .foregroundStyle(OffRecordColor.textYellow)
                    }
                }

                highlightedText(evidence?.snippet ?? entry.text ?? "")
                    .font(OffRecordTypography.bodySmall)
                    .foregroundStyle(OffRecordColor.textPrimary)
                    .lineSpacing(1.5)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(evidence?.snippet ?? entry.text ?? "")
                    .accessibilityIdentifier(evidence == nil ? "timeline.entrySnippet" : "timeline.evidenceSnippet")
            }
            .layoutPriority(1)

            if let evidence {
                VStack(alignment: .trailing, spacing: 4) {
                    Image(systemName: evidence.matchReason == .exact ? "text.magnifyingglass" : "brain.head.profile")
                        .foregroundStyle(OffRecordColor.brandLavenderDark)
                    Text(evidence.matchReason.rawValue)
                        .font(OffRecordTypography.labelSmall)
                        .foregroundStyle(OffRecordColor.textLavender)
                        .multilineTextAlignment(.trailing)
                }
                .frame(maxWidth: 74)
                .accessibilityIdentifier("timeline.evidenceReason.\(evidence.matchReason.rawValue)")
            }

            moodArt

            if isEditing {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(OffRecordColor.textInverse)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(OffRecordColor.textCoral))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete entry")
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .padding(.vertical, 14)
        .frame(minHeight: TimelineDesign.entryRowMinHeight)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(OffRecordColor.surfacePrimary.opacity(0.91))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(OffRecordColor.borderWarm.opacity(0.78), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.044), radius: 17, x: 0, y: 8)
        )
        .contentShape(RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("timeline.entryRow")
    }

    @ViewBuilder
    private var moodArt: some View {
        Image(mood.largeMoodAssetName)
            .resizable()
            .scaledToFit()
            .frame(width: TimelineDesign.moodArtSize, height: TimelineDesign.moodArtSize)
            .opacity(mood == .none ? 0.58 : 0.95)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func highlightedText(_ text: String) -> some View {
        if text.isEmpty {
            Text("Tap to add text")
                .foregroundStyle(OffRecordColor.textSecondary)
                .italic()
        } else if searchText.isEmpty {
            Text(text)
        } else {
            Text(attributedString(for: text))
        }
    }

    private func attributedString(for text: String) -> AttributedString {
        var attributedString = AttributedString(text)
        let searchLower = searchText.lowercased()
        let textLower = text.lowercased()

        var searchStart = textLower.startIndex
        while let range = textLower.range(of: searchLower, range: searchStart..<textLower.endIndex) {
            if let attrRange = Range(range, in: attributedString) {
                attributedString[attrRange].backgroundColor = OffRecordColor.brandYellow.opacity(0.32)
                attributedString[attrRange].foregroundColor = OffRecordColor.textPrimary
            }
            searchStart = range.upperBound
        }

        return attributedString
    }
}

enum TimelineEntryMetrics {
    static func wordCount(for entry: DiaryEntry) -> Int {
        guard let text = entry.text, !text.isEmpty else { return 0 }
        return text.split { $0.isWhitespace || $0.isNewline }.count
    }
}
