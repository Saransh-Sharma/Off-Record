//
//  FridayPromptPill.swift
//  OffRecord
//
//  Tappable suggested prompt pill for Friday chat.
//

import SwiftUI

struct FridayPromptPill: View {
    let question: FridayQuestion
    let title: String
    let isAsked: Bool
    let action: () -> Void

    var body: some View {
        let style = question.promptStyle

        Button(action: action) {
            HStack(spacing: OffRecordSpacing.md) {
                Image(systemName: question.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isAsked ? OffRecordColor.textTertiary : style.accent)
                    .frame(width: 22)

                Text(title)
                    .font(OffRecordTypography.labelLarge)
                    .foregroundStyle(isAsked ? OffRecordColor.textSecondary : OffRecordColor.textBrand)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .minimumScaleFactor(0.88)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 50)
            .background(isAsked ? OffRecordColor.surfaceWarm.opacity(0.78) : style.fill, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(isAsked ? OffRecordColor.borderSoft : style.border, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ask Friday: \(title)")
        .accessibilityIdentifier("friday.questionChip.\(question.accessibilityID)")
    }
}
