//
//  FridayEvidenceChip.swift
//  OffRecord
//
//  Compact, numbered evidence card for a cited journal memory.
//

import SwiftUI

struct FridayEvidenceChip: View {
    let evidence: EvidenceReference
    var number: Int?

    var body: some View {
        HStack(alignment: .top, spacing: OffRecordSpacing.md) {
            numberBadge

            VStack(alignment: .leading, spacing: OffRecordSpacing.xs) {
                HStack(spacing: OffRecordSpacing.sm) {
                    Text(evidence.date, format: .dateTime.month(.abbreviated).day().year())
                        .font(OffRecordTypography.labelSmall)
                        .foregroundStyle(OffRecordColor.textPrimary)

                    if let mood = evidence.mood, !mood.isEmpty {
                        Text(mood.capitalized)
                            .font(OffRecordTypography.labelSmall)
                            .foregroundStyle(OffRecordColor.textSecondary)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "arrow.up.right")
                        .font(OffRecordTypography.annotation)
                        .foregroundStyle(OffRecordColor.textTertiary)
                }

                Text(evidence.snippet)
                    .font(OffRecordTypography.metadata)
                    .foregroundStyle(OffRecordColor.textSecondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                Label(evidence.matchReason.displayName, systemImage: evidence.matchReason == .exact ? "text.magnifyingglass" : "quote.bubble")
                    .font(OffRecordTypography.annotation)
                    .foregroundStyle(OffRecordColor.textLavender)
            }
        }
        .padding(OffRecordSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OffRecordColor.backgroundLavenderTint.opacity(0.72), in: RoundedRectangle(cornerRadius: OffRecordRadius.sm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: OffRecordRadius.sm, style: .continuous)
                .stroke(OffRecordColor.borderSoft, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: OffRecordRadius.sm, style: .continuous))
    }

    @ViewBuilder
    private var numberBadge: some View {
        if let number {
            Text("\(number)")
                .font(OffRecordTypography.labelSmall.monospacedDigit())
                .foregroundStyle(OffRecordColor.textOnAccent)
                .frame(minWidth: 22, minHeight: 22)
                .background(OffRecordColor.brandLavenderDark, in: Circle())
        } else {
            Image(systemName: "quote.bubble.fill")
                .font(OffRecordTypography.metadata)
                .foregroundStyle(OffRecordColor.textLavender)
                .frame(width: 22)
        }
    }

    static func spokenDate(_ date: Date) -> String {
        date.formatted(date: .long, time: .omitted)
    }

    static func accessibilityLabel(for evidence: EvidenceReference, number: Int) -> String {
        var parts = ["Source \(number)", spokenDate(evidence.date)]
        if let mood = evidence.mood, !mood.isEmpty {
            parts.append("mood \(mood.capitalized)")
        }
        parts.append(evidence.snippet)
        return parts.joined(separator: ", ")
    }
}
