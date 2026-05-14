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
    let numberSize: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: OffRecordSpacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: OffRecordSpacing.xs) {
                Text("\(currentStreak)")
                    .font(.system(size: numberSize, weight: .bold, design: .rounded))
                    .foregroundStyle(accentColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(dayLabel)
                    .font(.title3)
                    .foregroundStyle(OffRecordColor.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            Text(statusMessage)
                .font(.subheadline)
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
        accentColor: OffRecordColor.textPeach,
        numberSize: 52
    )
    .padding()
}
