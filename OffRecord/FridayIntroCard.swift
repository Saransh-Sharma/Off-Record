//
//  FridayIntroCard.swift
//  OffRecord
//
//  Warm introduction card for Friday's empty chat state.
//

import SwiftUI

struct FridayIntroCard: View {
    let userName: String
    let mode: FridayWarmMinimalMode

    var body: some View {
        VStack(alignment: .leading, spacing: OffRecordSpacing.md) {
            Text(title)
                .font(OffRecordTypography.titleLarge)
                .foregroundStyle(OffRecordColor.textBrand)

            Text(bodyText)
                .font(OffRecordTypography.bodyMedium)
                .lineSpacing(4)
                .foregroundStyle(OffRecordColor.textBrand.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(OffRecordSpacing.xxl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OffRecordColor.surfacePrimary.opacity(0.95), in: RoundedRectangle(cornerRadius: 28))
        .overlay {
            RoundedRectangle(cornerRadius: 28)
                .stroke(OffRecordColor.borderSoft, lineWidth: 1)
        }
        .offRecordShadow(.card)
    }

    private var title: String {
        switch mode {
        case .noJournalData:
            return "I don’t know you yet."
        case .indexing:
            return "I’m getting your journal ready."
        case .warm:
            return FridayPersonality.greeting
        }
    }

    private var bodyText: String {
        switch mode {
        case .noJournalData:
            return "Write or record a few entries and I’ll start seeing patterns. You can still talk to me now."
        case .indexing(let statusFragment):
            let status = Self.sentence(from: statusFragment)
            return status.isEmpty ? "I’ll be ready soon." : "\(status) I’ll be ready soon."
        case .warm:
            return Personalization.appendFirstName(to: FridayPersonality.invitation, name: userName) + "."
        }
    }

    /// Ends a status fragment ("Building…", "12 of 40 entries") as a sentence without doubling punctuation.
    private static func sentence(from fragment: String) -> String {
        let trimmed = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last else { return "" }
        return ".…?".contains(last) ? trimmed : trimmed + "."
    }
}
