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
    @ScaledMetric(relativeTo: .largeTitle) private var streakNumberSize: CGFloat = 52
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

    private var statusTitle: String {
        isActive ? "Streak alive" : "Ready to restart"
    }

    private var statusMessage: String {
        isActive ? "Your writing rhythm is intact." : "A single entry restarts your streak."
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

    var body: some View {
        VStack(alignment: .leading, spacing: OffRecordSpacing.lg) {
            HStack(alignment: .center, spacing: OffRecordSpacing.md) {
                Text("Writing Streak")
                    .font(.headline)
                    .foregroundStyle(OffRecordColor.textHeading)

                Spacer(minLength: OffRecordSpacing.sm)

                Text(statusTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accentColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, OffRecordSpacing.md)
                    .padding(.vertical, OffRecordSpacing.xs)
                    .background(accentFill.opacity(isActive ? 0.18 : 0.14), in: Capsule())
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: OffRecordSpacing.lg) {
                    StreakSummaryView(
                        currentStreak: currentStreak,
                        dayLabel: dayLabel,
                        statusMessage: statusMessage,
                        accentColor: accentColor,
                        numberSize: streakNumberSize
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
                        accentColor: accentColor,
                        numberSize: streakNumberSize
                    )
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: OffRecordSpacing.md) {
                    StreakMetricColumnView(title: "Longest", value: "\(longestStreak) \(longestStreak == 1 ? "day" : "days")")

                    Divider()
                        .frame(height: 34)

                    StreakMetricColumnView(title: "This Month", value: "\(entriesThisMonth) \(entriesThisMonth == 1 ? "entry" : "entries")")

                    Divider()
                        .frame(height: 34)

                    StreakMetricColumnView(title: "Total", value: "\(totalEntries) \(totalEntries == 1 ? "entry" : "entries")")
                }

                VStack(alignment: .leading, spacing: OffRecordSpacing.sm) {
                    StreakMetricColumnView(title: "Longest", value: "\(longestStreak) \(longestStreak == 1 ? "day" : "days")")
                    StreakMetricColumnView(title: "This Month", value: "\(entriesThisMonth) \(entriesThisMonth == 1 ? "entry" : "entries")")
                    StreakMetricColumnView(title: "Total", value: "\(totalEntries) \(totalEntries == 1 ? "entry" : "entries")")
                }
            }
        }
        .padding()
        .offRecordContentCard(cornerRadius: OffRecordRadius.xl, fill: cardFill)
        .accessibilityElement(children: .combine)
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
