//
//  Settings+Streaks.swift
//  OffRecord
//
//  Streak settings: daily or weekly streaks, and the rest day (grace day)
//  that lets one missed day a week leave a daily streak running. The rules
//  are in `JournalStreak`; Today, Insights, and the widgets all follow them.
//

import SwiftUI

struct StreakSettingsSection: View {
    @ObservedObject private var goalManager = GoalManager.shared

    private var footer: String {
        switch goalManager.streakCadence {
        case .daily:
            return goalManager.allowsStreakGraceDay
                ? String(localized: "A daily streak allows one missed day a week.")
                : String(localized: "A daily streak counts days in a row with an entry.")
        case .weekly:
            let target = goalManager.streakRules.weeklyTarget
            return target > 1
                ? String(localized: "A week counts when it meets your weekly goal of \(target) days.")
                : String(localized: "A week counts when it has at least one entry.")
        }
    }

    var body: some View {
        SettingsCard(
            title: String(localized: "Streak", comment: "Settings section: journaling streak"),
            footer: footer,
            systemImage: "flame.fill",
            tint: OffRecordColor.textPeach,
            fill: OffRecordColor.surfacePeach
        ) {
            Picker(String(localized: "Count", comment: "Settings picker: count the streak daily or weekly"), selection: $goalManager.streakCadence) {
                Text("Daily", comment: "Streak counted in days").tag(StreakCadence.daily)
                Text("Weekly", comment: "Streak counted in weeks").tag(StreakCadence.weekly)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("settings.streak.cadence")

            if goalManager.streakCadence == .daily {
                Toggle(String(localized: "Allow a Rest Day", comment: "Settings toggle: one missed day a week keeps a daily streak"), isOn: $goalManager.allowsStreakGraceDay)
                    .accessibilityIdentifier("settings.streak.restDay")
            }
        }
        .accessibilityIdentifier("settings.streak.section")
    }
}
