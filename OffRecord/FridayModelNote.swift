//
//  FridayModelNote.swift
//  OffRecord
//
//  The one-time note in Friday's chat when Apple Intelligence can't be used:
//  she still answers, from short summaries of the entries.
//

import SwiftUI

struct FridayModelNote: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: OffRecordSpacing.sm) {
            Image(systemName: "text.bubble")
                .font(OffRecordTypography.labelMedium)
                .foregroundStyle(OffRecordColor.textLavender)
                .accessibilityHidden(true)
            Text(text)
                .font(OffRecordTypography.bodySmall)
                .foregroundStyle(OffRecordColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(OffRecordSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OffRecordColor.surfacePrimary.opacity(0.72), in: RoundedRectangle(cornerRadius: OffRecordRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: OffRecordRadius.lg, style: .continuous)
                .stroke(OffRecordColor.borderSoft, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("friday.modelNote")
    }
}

#Preview {
    FridayModelNote(text: FridayModelAvailability.appleIntelligenceOff.chatNote ?? "")
        .padding()
}
