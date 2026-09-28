//
//  InsightEvidenceSheet.swift
//  OffRecord
//
//  "Why am I seeing this?" for insight cards: the rationale behind an insight
//  and the journal entries that support it, each one tappable.
//

import CoreData
import SwiftUI

struct InsightEvidenceContext: Identifiable {
    let id: String
    let title: String
    let summary: String
    let rationale: String
    let entries: [DiaryEntry]
}

extension DiaryEntry {
    /// Matches `JournalEntrySnapshot.id`, so insight evidence resolves back to entries.
    var insightEvidenceKey: String {
        id?.uuidString ?? objectID.uriRepresentation().absoluteString
    }
}

extension Sequence where Element == DiaryEntry {
    /// Entries matching `keys`, in the order the keys were given.
    func resolvingInsightEvidence(_ keys: [String]) -> [DiaryEntry] {
        guard !keys.isEmpty else { return [] }
        var byKey: [String: DiaryEntry] = [:]
        for entry in self { byKey[entry.insightEvidenceKey] = entry }
        return keys.compactMap { byKey[$0] }
    }
}

/// Small "Why?" affordance shown on insight cards that have supporting entries.
struct InsightWhyButton: View {
    var title = String(localized: "Why?", comment: "Button on an insight card that explains where it came from")
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "questionmark.circle")
                .font(OffRecordTypography.labelSmall)
                .foregroundStyle(OffRecordColor.textLavender)
                .padding(.horizontal, OffRecordSpacing.md)
                .padding(.vertical, OffRecordSpacing.xs + 2)
                .background(OffRecordColor.backgroundLavenderTint, in: Capsule())
                .overlay(Capsule().stroke(OffRecordColor.borderSoft, lineWidth: 1))
                .frame(minHeight: OffRecordLayout.minimumTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows the entries behind this insight.")
    }
}

struct InsightEvidenceSheet: View {
    let context: InsightEvidenceContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: OffRecordSpacing.xl) {
                    header

                    if !context.rationale.isEmpty {
                        rationaleCard
                    }

                    VStack(alignment: .leading, spacing: OffRecordSpacing.md) {
                        Text("Based On")
                            .font(OffRecordTypography.sectionTitle)
                            .foregroundStyle(OffRecordColor.textHeading)
                            .accessibilityAddTraits(.isHeader)

                        if context.entries.isEmpty {
                            InsightChartEmptyState(
                                systemImage: "doc.text.magnifyingglass",
                                message: String(localized: "These entries were deleted.")
                            )
                        } else {
                            ForEach(context.entries, id: \.objectID) { entry in
                                NavigationLink {
                                    EntryDetailView(entry: entry)
                                } label: {
                                    InsightEvidenceRow(entry: entry)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("insights.evidence.entry")
                            }
                        }
                    }

                }
                .padding(OffRecordSpacing.screenX)
                .frame(maxWidth: OffRecordLayout.readableContentWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(OffRecordAppBackground().ignoresSafeArea())
            .navigationTitle("Why You’re Seeing This")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: OffRecordSpacing.sm) {
            Text(context.title)
                .font(OffRecordTypography.titleSmall)
                .foregroundStyle(OffRecordColor.textHeading)
                .fixedSize(horizontal: false, vertical: true)
            if !context.summary.isEmpty {
                Text(context.summary)
                    .font(OffRecordTypography.bodyMedium)
                    .foregroundStyle(OffRecordColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var rationaleCard: some View {
        HStack(alignment: .top, spacing: OffRecordSpacing.md) {
            OffRecordIconBubble(systemImage: "sparkles", tint: OffRecordColor.textLavender, size: 30, iconSize: 13)
            VStack(alignment: .leading, spacing: OffRecordSpacing.xxs) {
                Text("How I Got This")
                    .font(OffRecordTypography.labelSmall)
                    .foregroundStyle(OffRecordColor.textLavender)
                Text(context.rationale)
                    .font(OffRecordTypography.bodySmall)
                    .foregroundStyle(OffRecordColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(OffRecordSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OffRecordColor.surfacePrimary, in: RoundedRectangle(cornerRadius: OffRecordRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: OffRecordRadius.md, style: .continuous)
                .stroke(OffRecordColor.borderSoft, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

/// One cited entry, styled after Friday's evidence chips.
struct InsightEvidenceRow: View {
    @ObservedObject var entry: DiaryEntry

    private var mood: Mood {
        Mood(rawValue: (entry.value(forKey: "mood") as? String) ?? "") ?? .none
    }

    private var snippet: String {
        let text = (entry.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            return text.count > 180 ? String(text.prefix(180)).trimmingCharacters(in: .whitespaces) + "…" : text
        }
        if entry.hasStartedEntryAudio { return String(localized: "Recording", comment: "Placeholder snippet for an entry with only a voice recording") }
        if entry.hasStartedEntryPhotos { return String(localized: "Photo", comment: "Placeholder snippet for an entry with only photos") }
        return String(localized: "Mood", comment: "Placeholder snippet for an entry with only a mood")
    }

    private var date: Date { entry.date ?? entry.createdAt ?? Date() }

    var body: some View {
        HStack(alignment: .top, spacing: OffRecordSpacing.md) {
            if mood != .none {
                MiniMoodIcon(mood: mood, size: 24, opacity: 0.95)
            } else {
                Image(systemName: "quote.bubble.fill")
                    .font(OffRecordTypography.metadata)
                    .foregroundStyle(OffRecordColor.textLavender)
                    .frame(width: 24)
            }

            VStack(alignment: .leading, spacing: OffRecordSpacing.xs) {
                HStack(spacing: OffRecordSpacing.sm) {
                    Text(date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
                        .font(OffRecordTypography.labelSmall)
                        .foregroundStyle(OffRecordColor.textPrimary)
                    if mood != .none {
                        Text(mood.displayName)
                            .font(OffRecordTypography.labelSmall)
                            .foregroundStyle(OffRecordColor.textSecondary)
                    }
                }
                Text(snippet)
                    .font(OffRecordTypography.metadata)
                    .foregroundStyle(OffRecordColor.textSecondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(OffRecordTypography.labelSmall)
                .foregroundStyle(OffRecordColor.textTertiary)
                .padding(.top, OffRecordSpacing.xxs)
                .accessibilityHidden(true)
        }
        .padding(OffRecordSpacing.md)
        .frame(maxWidth: .infinity, minHeight: OffRecordLayout.minimumTapTarget, alignment: .leading)
        .background(OffRecordColor.backgroundLavenderTint.opacity(0.72), in: RoundedRectangle(cornerRadius: OffRecordRadius.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: OffRecordRadius.sm, style: .continuous)
                .stroke(OffRecordColor.borderSoft, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: OffRecordRadius.sm, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let dateText = date.formatted(date: .long, time: .omitted)
        if mood != .none {
            return String(localized: "Entry from \(dateText), \(mood.displayName). \(snippet)")
        }
        return String(localized: "Entry from \(dateText). \(snippet)")
    }
}
