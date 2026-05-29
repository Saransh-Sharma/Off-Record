//
//  FridayEvidenceChip.swift
//  OffRecord
//
//  Compact evidence card for a cited journal memory.
//

import SwiftUI

struct FridayEvidenceChip: View {
    let evidence: EvidenceReference
    var chipAccessibilityIdentifier: String? = "friday.evidenceChip"

    var body: some View {
        HStack(alignment: .top, spacing: OffRecordSpacing.md) {
            Image(systemName: evidence.matchReason == .exact ? "text.magnifyingglass" : "quote.bubble.fill")
                .font(OffRecordTypography.metadata)
                .foregroundStyle(OffRecordColor.textLavender)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: OffRecordSpacing.xs) {
                HStack(spacing: OffRecordSpacing.sm) {
                    Text(evidence.date, format: .dateTime.month(.abbreviated).day().year())
                        .font(OffRecordTypography.labelSmall)
                        .foregroundStyle(OffRecordColor.textPrimary)

                    if let mood = evidence.mood, !mood.isEmpty {
                        Text(mood.capitalized)
                            .font(OffRecordTypography.labelSmall)
                            .foregroundStyle(OffRecordColor.textSecondary)
                            .accessibilityIdentifier("friday.evidenceChip.mood")
                    }
                }

                Text(evidence.snippet)
                    .font(OffRecordTypography.metadata)
                    .foregroundStyle(OffRecordColor.textSecondary)
                    .lineLimit(3)
                    .accessibilityIdentifier("friday.evidenceChip.snippet")

                Text(evidence.matchReason.rawValue)
                    .font(OffRecordTypography.labelSmall)
                    .foregroundStyle(OffRecordColor.textLavender)
                    .accessibilityIdentifier("friday.evidenceChip.reason")
            }
        }
        .padding(OffRecordSpacing.md)
        .background(OffRecordColor.backgroundLavenderTint.opacity(0.72), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(OffRecordColor.borderSoft, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .modifier(OptionalAccessibilityIdentifier(identifier: chipAccessibilityIdentifier))
    }
}

private struct OptionalAccessibilityIdentifier: ViewModifier {
    let identifier: String?

    func body(content: Content) -> some View {
        if let identifier {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}
