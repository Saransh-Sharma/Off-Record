//
//  StreakSummaryView.swift
//  OffRecord
//
//  Current streak number and state copy for the Insights card.
//

import SwiftUI

struct StreakSummaryView: View {
    let currentStreak: Int
    let dayLabel: String
    let statusMessage: String
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: OffRecordSpacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: OffRecordSpacing.xs) {
                Text("\(currentStreak)")
                    .font(OffRecordTypography.numberLarge)
                    .foregroundStyle(accentColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(dayLabel)
                    .font(OffRecordTypography.titleSmall)
                    .foregroundStyle(OffRecordColor.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            Text(statusMessage)
                .font(OffRecordTypography.bodySmall)
                .foregroundStyle(OffRecordColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    StreakSummaryView(
        currentStreak: 7,
        dayLabel: "days",
        statusMessage: "Your writing rhythm is intact.",
        accentColor: OffRecordColor.textPeach
    )
    .padding()
}
