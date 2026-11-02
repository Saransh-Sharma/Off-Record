//
//  GoalManager.swift
//  OffRecord
//
//  Manages journaling goals, streak settings, and milestone tracking.
//  The streak rules themselves live in `JournalStreak` (OffRecordSystemShared)
//  so the widgets count streaks exactly like the app.
//

import Foundation
import UserNotifications
import CoreData

final class GoalManager: ObservableObject {
    static let shared = GoalManager()

    private let goalEnabledKey = "dvx_goal_enabled"
    private let goalTargetKey = "dvx_goal_target"
    private let goalNotifyKey = "dvx_goal_notify"
    private let lastMilestoneKey = "dvx_last_milestone"

    static let streakCadenceKey = "offrecord_streak_cadence"
    static let streakGraceDayKey = "offrecord_streak_grace_day"

    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: goalEnabledKey)
            streakRulesDidChange()
        }
    }

    @Published var weeklyTarget: Int {
        didSet {
            UserDefaults.standard.set(weeklyTarget, forKey: goalTargetKey)
            streakRulesDidChange()
        }
    }

    /// Daily or weekly streaks.
    @Published var streakCadence: StreakCadence {
        didSet {
            UserDefaults.standard.set(streakCadence.rawValue, forKey: Self.streakCadenceKey)
            streakRulesDidChange()
        }
    }

    /// Daily streaks only: one missed day in any 7 days keeps the streak (a "rest day").
    @Published var allowsStreakGraceDay: Bool {
        didSet {
            UserDefaults.standard.set(allowsStreakGraceDay, forKey: Self.streakGraceDayKey)
            streakRulesDidChange()
        }
    }

    /// The rules every streak in the app and the widgets follows.
    var streakRules: StreakRules {
        Self.streakRules(
            cadence: streakCadence,
            allowsGraceDay: allowsStreakGraceDay,
            goalEnabled: isEnabled,
            weeklyTarget: weeklyTarget
        )
    }

    /// The saved streak rules, readable off the main thread (analytics, widget export).
    static func storedStreakRules(defaults: UserDefaults = .standard) -> StreakRules {
        let savedTarget = defaults.integer(forKey: "dvx_goal_target")
        return streakRules(
            cadence: defaults.string(forKey: streakCadenceKey).flatMap(StreakCadence.init(rawValue:)) ?? .daily,
            allowsGraceDay: defaults.object(forKey: streakGraceDayKey) as? Bool ?? true,
            goalEnabled: defaults.bool(forKey: "dvx_goal_enabled"),
            weeklyTarget: savedTarget > 0 ? savedTarget : 3
        )
    }

    /// A weekly streak counts weeks that meet the Weekly Goal while it's on, and weeks
    /// with any entry while it's off.
    static func streakRules(cadence: StreakCadence, allowsGraceDay: Bool, goalEnabled: Bool, weeklyTarget: Int) -> StreakRules {
        StreakRules(cadence: cadence, allowsGraceDay: allowsGraceDay, weeklyTarget: goalEnabled ? weeklyTarget : 1)
    }

    @Published var notifyOnGoal: Bool {
        didSet {
            UserDefaults.standard.set(notifyOnGoal, forKey: goalNotifyKey)
        }
    }

    static let milestones = [7, 14, 30, 50, 100, 200, 365]

    private init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: goalEnabledKey)
        let savedTarget = UserDefaults.standard.integer(forKey: goalTargetKey)
        self.weeklyTarget = savedTarget > 0 ? savedTarget : 3
        self.notifyOnGoal = UserDefaults.standard.bool(forKey: goalNotifyKey)
        let storedRules = Self.storedStreakRules()
        self.streakCadence = storedRules.cadence
        self.allowsStreakGraceDay = storedRules.allowsGraceDay
    }

    /// Widgets read the rules from their snapshot, so a change rewrites it.
    private func streakRulesDidChange() {
        Task { @MainActor in
            WidgetSnapshotExporter.shared.scheduleExport(after: .milliseconds(300))
        }
    }

    // MARK: - Weekly Progress

    func entriesThisWeek(from entries: [DiaryEntry]) -> Int {
        let calendar = Calendar.current
        let now = Date()
        guard let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) else { return 0 }

        let uniqueDays = Set(entries.compactMap { entry -> Date? in
            guard let date = entry.date, date >= weekStart else { return nil }
            return calendar.startOfDay(for: date)
        })

        return uniqueDays.count
    }

    func progressThisWeek(from entries: [DiaryEntry]) -> Double {
        guard weeklyTarget > 0 else { return 0 }
        return min(1.0, Double(entriesThisWeek(from: entries)) / Double(weeklyTarget))
    }

    func daysRemainingInWeek() -> Int {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: Date())
        // Week starts on Sunday (1), so remaining = 7 - weekday + 1
        return 8 - weekday
    }

    // MARK: - Milestone Tracking

    /// Milestones are counted in days, so weekly streaks don't celebrate them.
    func checkMilestone(currentStreak: Int) -> Int? {
        guard streakCadence == .daily else { return nil }
        let lastMilestone = UserDefaults.standard.integer(forKey: lastMilestoneKey)

        for milestone in Self.milestones {
            if currentStreak >= milestone && milestone > lastMilestone {
                UserDefaults.standard.set(milestone, forKey: lastMilestoneKey)
                return milestone
            }
        }

        return nil
    }

    // MARK: - Goal Notification

    func scheduleGoalNotification(entriesThisWeek: Int) {
        guard notifyOnGoal, isEnabled else { return }
        guard entriesThisWeek >= weeklyTarget else { return }

        let center = UNUserNotificationCenter.current()
        let id = "dvx_goal_reached"
        center.removePendingNotificationRequests(withIdentifiers: [id])

        let content = UNMutableNotificationContent()
        // `entriesThisWeek` counts distinct days with an entry (see `entriesThisWeek(from:)`).
        content.title = String(localized: "Weekly Goal Reached")
        content.body = String(AttributedString(localized: "You journaled ^[\(entriesThisWeek) day](inflect: true) this week.").characters)
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        center.add(request, withCompletionHandler: nil)
    }
}
