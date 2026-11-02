//
//  StreakCopy.swift
//  OffRecordSystemShared
//
//  Streak wording shared by the app and the widgets. It states the count
//  and never frames a streak as something to lose (Voice, OffRecord Design.md).
//

import Foundation

enum StreakCopy {
    /// "7-day streak", "3-week streak".
    static func label(count: Int, cadence: StreakCadence) -> String {
        switch cadence {
        case .daily:
            return String(localized: "\(count)-day streak")
        case .weekly:
            return String(localized: "\(count)-week streak")
        }
    }

    /// "7-day streak.", for insight descriptions.
    static func sentence(count: Int, cadence: StreakCadence) -> String {
        switch cadence {
        case .daily:
            return String(localized: "\(count)-day streak.", comment: "Insight description, e.g. “7-day streak.”")
        case .weekly:
            return String(localized: "\(count)-week streak.", comment: "Insight description, e.g. “4-week streak.”")
        }
    }

    /// "3-day streak so far."
    static func soFar(count: Int, cadence: StreakCadence) -> String {
        switch cadence {
        case .daily:
            return String(localized: "\(count)-day streak so far.")
        case .weekly:
            return String(localized: "\(count)-week streak so far.")
        }
    }

    /// The unit shown after a bare streak number: "day", "days", "week", "weeks".
    static func unit(count: Int, cadence: StreakCadence) -> String {
        switch (cadence, count == 1) {
        case (.daily, true):
            return String(localized: "day", comment: "Unit shown after a streak count of 1")
        case (.daily, false):
            return String(localized: "days", comment: "Unit shown after a streak count other than 1")
        case (.weekly, true):
            return String(localized: "week", comment: "Unit shown after a weekly streak count of 1")
        case (.weekly, false):
            return String(localized: "weeks", comment: "Unit shown after a weekly streak count other than 1")
        }
    }

    /// "14 days", "1 week".
    static func duration(count: Int, cadence: StreakCadence) -> String {
        switch cadence {
        case .daily:
            return String(AttributedString(localized: "^[\(count) day](inflect: true)").characters)
        case .weekly:
            return String(AttributedString(localized: "^[\(count) week](inflect: true)").characters)
        }
    }

    /// How a streak is counted, for "Why am I seeing this?".
    static func rationale(for rules: StreakRules) -> String {
        switch rules.cadence {
        case .daily where rules.allowsGraceDay:
            return String(localized: "Days with an entry, allowing one rest day a week.")
        case .daily:
            return String(localized: "Days in a row with at least one entry.")
        case .weekly where rules.weeklyTarget > 1:
            return String(localized: "Weeks in a row that met your weekly goal.")
        case .weekly:
            return String(localized: "Weeks in a row with at least one entry.")
        }
    }
}
