//
//  FridayEvidenceRail.swift
//  OffRecord
//
//  Evidence links under Friday answers.
//

import SwiftUI

struct FridayEvidenceRail: View {
    let evidence: [EvidenceReference]
    let entryProvider: (UUID) -> DiaryEntry?

    @State private var selectedEntry: DiaryEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: OffRecordSpacing.sm) {
            Text("Evidence from your journal")
                .font(OffRecordTypography.labelSmall)
                .foregroundStyle(OffRecordColor.textLavender)
                .accessibilityIdentifier("friday.evidenceHeader")

            ForEach(evidence.prefix(3)) { item in
                if let entry = entryProvider(item.entryID) {
                    Button {
                        selectedEntry = entry
                    } label: {
                        FridayEvidenceChip(evidence: item, chipAccessibilityIdentifier: nil)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("friday.evidenceChip")
                } else {
                    FridayEvidenceChip(evidence: item)
                }
            }
        }
        .padding(.top, 2)
        .frame(maxWidth: 320, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("friday.evidenceRail")
        .navigationDestination(
            isPresented: Binding(
                get: { selectedEntry != nil },
                set: { isPresented in
                    if !isPresented {
                        selectedEntry = nil
                    }
                }
            )
        ) {
            if let selectedEntry {
                EntryDetailView(entry: selectedEntry)
            }
        }
    }
}
