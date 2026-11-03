//
//  EntryDetailView+Support.swift
//  OffRecord
//
//  How Friday may respond to this entry, and the support card shown instead
//  of her questions and notes when the text reads as high risk.
//

import SwiftUI
import JournalFoundation

extension EntryDetailView {
    /// How Friday may respond to this entry; high-risk text is never analyzed or asked about.
    var entryResponseMode: SensitiveResponseMode {
        JournalRiskClassifier.responseMode(for: text)
    }

    var entrySupportCard: some View {
        VStack(alignment: .leading, spacing: OffRecordSpacing.md) {
            Text(FridayPersonality.riskSafeSupport)
                .font(OffRecordTypography.bodyLarge)
                .foregroundStyle(OffRecordColor.textBrand)
                .fixedSize(horizontal: false, vertical: true)
            GetSupportButton()
        }
        .padding(OffRecordSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .offRecordCard(cornerRadius: OffRecordRadius.lg)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("entryDetail.support")
    }
}
