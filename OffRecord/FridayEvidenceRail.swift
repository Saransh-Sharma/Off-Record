//
//  FridayEvidenceRail.swift
//  OffRecord
//
//  Numbered evidence under Friday answers. Numbers match the [n] markers in
//  the answer text; tapping a source zooms into the entry.
//

import SwiftUI

struct FridayEvidenceRail: View {
    static let maximumSources = 4

    let messageID: UUID
    let evidence: [EvidenceReference]
    let maxWidth: CGFloat
    let namespace: Namespace.ID
    let entryProvider: (UUID) -> DiaryEntry?
    let onOpen: (FridayEvidenceSelection) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: OffRecordSpacing.sm) {
            Text("Sources")
                .font(OffRecordTypography.labelSmall)
                .foregroundStyle(OffRecordColor.textLavender)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("friday.evidenceHeader")

            ForEach(Array(evidence.prefix(Self.maximumSources).enumerated()), id: \.element.id) { index, item in
                let number = index + 1
                let sourceID = "\(messageID.uuidString)-\(item.id)"
                if let entry = entryProvider(item.entryID) {
                    Button {
                        onOpen(FridayEvidenceSelection(entry: entry, sourceID: sourceID))
                    } label: {
                        FridayEvidenceChip(evidence: item, number: number)
                    }
                    .buttonStyle(.plain)
                    .matchedTransitionSource(id: sourceID, in: namespace)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(FridayEvidenceChip.accessibilityLabel(for: item, number: number))
                    .accessibilityValue(item.matchReason.displayName)
                    .accessibilityHint("Opens the entry.")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("friday.evidenceChip")
                } else {
                    FridayEvidenceChip(evidence: item, number: number)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(FridayEvidenceChip.accessibilityLabel(for: item, number: number))
                        .accessibilityValue(item.matchReason.displayName)
                        .accessibilityIdentifier("friday.evidenceChip")
                }
            }
        }
        .padding(.top, OffRecordSpacing.xxs)
        .frame(maxWidth: maxWidth, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("friday.evidenceRail")
    }
}
