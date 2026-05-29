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
        .shadow(color: Color.black.opacity(0.06), radius: 28, x: 0, y: 10)
    }

    private var title: String {
        switch mode {
        case .noJournalData:
            return "I need a little context."
        case .indexing:
            return "I’m getting your journal ready."
        case .warm:
            return "I’m Friday."
        }
    }

    private var bodyText: String {
        switch mode {
        case .noJournalData:
            return "Write or record a few entries, then come back and ask me what’s been repeating. You can still talk to me about what’s on your mind."
        case .indexing(let message):
            return "\(message) I’ll answer from entries stored on this device once memory is ready."
        case .warm:
            return Personalization.appendFirstName(
                to: "Tell me what you’re carrying, or ask what patterns I’ve noticed in your journal",
                name: userName
            )
        }
    }
}
