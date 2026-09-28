//
//  StreakCardView.swift
//  OffRecord
//
//  Insights streak card with active and inactive fire artwork.
//

import SwiftUI

struct StreakCardView: View {
    let currentStreak: Int
    let longestStreak: Int
    let entriesThisMonth: Int
    let totalEntries: Int
    let isIPad: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title2) private var fireBaseSize: CGFloat = 118

    private var isActive: Bool {
        currentStreak > 0
    }

    private var fireImageName: String {
        isActive ? "StreakFire" : "StreakFireInactive"
    }

    private var accentColor: Color {
        isActive ? OffRecordColor.textPeach : OffRecordColor.textLavender
    }

    private var accentFill: Color {
        isActive ? OffRecordColor.brandPeach : OffRecordColor.brandLavender
    }

    private var cardFill: Color {
        isActive ? OffRecordColor.surfacePeach : OffRecordColor.surfaceLavender
    }

    /// Nothing to say while a streak is running; at 0 it invites a first entry.
    private var statusMessage: String? {
        isActive ? nil : "Write today to start a streak."
    }

    private var fireSize: CGFloat {
        if dynamicTypeSize.isAccessibilitySize {
            return isIPad ? 112 : 92
        }

        return min(fireBaseSize, isIPad ? 140 : 120)
    }

    private var dayLabel: String {
        currentStreak == 1 ? "day" : "days"
    }

    private var longestValue: String { Self.inflected("^[\(longestStreak) day](inflect: true)") }
    private var thisMonthValue: String { Self.inflected("^[\(entriesThisMonth) entry](inflect: true)") }
    private var totalValue: String { Self.inflected("^[\(totalEntries) entry](inflect: true)") }

    private static func inflected(_ value: String.LocalizationValue) -> String {
        String(AttributedString(localized: value).characters)
    }

    private var accessibilitySummary: String {
        var summary = "\(currentStreak) \(dayLabel)."
        if let statusMessage { summary += " \(statusMessage)" }
        return summary + " Longest \(longestValue), \(thisMonthValue) this month, \(totalValue) total."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OffRecordSpacing.lg) {
            HStack(alignment: .center, spacing: OffRecordSpacing.md) {
                Text("Streak")
                    .font(OffRecordTypography.sectionTitle)
                    .foregroundStyle(OffRecordColor.textHeading)

                Spacer(minLength: OffRecordSpacing.sm)
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: OffRecordSpacing.lg) {
                    StreakSummaryView(
                        currentStreak: currentStreak,
                        dayLabel: dayLabel,
                        statusMessage: statusMessage,
                        accentColor: accentColor
                    )

                    Spacer(minLength: OffRecordSpacing.md)

                    StreakFireArtworkView(
                        imageName: fireImageName,
                        size: fireSize,
                        accentFill: accentFill,
                        isActive: isActive
                    )
                }

                VStack(alignment: .leading, spacing: OffRecordSpacing.md) {
                    HStack {
                        Spacer(minLength: 0)
                        StreakFireArtworkView(
                            imageName: fireImageName,
                            size: fireSize,
                            accentFill: accentFill,
                            isActive: isActive
                        )
                        Spacer(minLength: 0)
                    }

                    StreakSummaryView(
                        currentStreak: currentStreak,
                        dayLabel: dayLabel,
                        statusMessage: statusMessage,
                        accentColor: accentColor
                    )
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: OffRecordSpacing.md) {
                    StreakMetricColumnView(title: "Longest", value: longestValue)

                    Divider()
                        .frame(maxHeight: 44)

                    StreakMetricColumnView(title: "This Month", value: thisMonthValue)

                    Divider()
                        .frame(maxHeight: 44)

                    StreakMetricColumnView(title: "Total", value: totalValue)
                }

                VStack(alignment: .leading, spacing: OffRecordSpacing.sm) {
                    StreakMetricColumnView(title: "Longest", value: longestValue)
                    StreakMetricColumnView(title: "This Month", value: thisMonthValue)
                    StreakMetricColumnView(title: "Total", value: totalValue)
                }
            }
        }
        .padding()
        .offRecordContentCard(cornerRadius: OffRecordRadius.xl, fill: cardFill)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Streak")
        .accessibilityValue(accessibilitySummary)
    }
}

#Preview("Active Streak") {
    StreakCardView(
        currentStreak: 7,
        longestStreak: 14,
        entriesThisMonth: 18,
        totalEntries: 82,
        isIPad: false
    )
    .padding()
}

#Preview("Inactive Streak") {
    StreakCardView(
        currentStreak: 0,
        longestStreak: 14,
        entriesThisMonth: 4,
        totalEntries: 82,
        isIPad: false
    )
    .padding()
}
