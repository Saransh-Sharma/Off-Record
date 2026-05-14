//
//  StreakMetricColumnView.swift
//  OffRecord
//
//  Compact metric label used by the Insights streak card.
//

import SwiftUI

struct StreakMetricColumnView: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: OffRecordSpacing.xs) {
            Text(title)
                .font(.caption)
                .foregroundStyle(OffRecordColor.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(OffRecordColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    StreakMetricColumnView(title: "Longest", value: "14 days")
        .padding()
}
