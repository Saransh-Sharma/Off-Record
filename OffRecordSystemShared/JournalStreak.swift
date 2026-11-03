//
//  JournalStreak.swift
//  OffRecordSystemShared
//
//  Streak math shared by the app (Today, Insights, milestones) and the
//  widgets, so every surface shows the same number.
//
//  Rules:
//  - Daily streaks count the days with an entry in the current run.
//    Today is open until it ends, so a day without an entry yet never ends
//    a streak.
//  - With the grace day on (the default), one missed day in any 7 days in a
//    row doesn't end a daily streak. Two missed days in a row, or two misses
//    less than 7 days apart, do. A missed day keeps the run going but isn't
//    counted, so the number is always days with an entry. Settings calls the
//    grace day a "rest day".
//  - Weekly streaks count weeks in a row with at least `weeklyTarget` days
//    with an entry (the Weekly Goal when it's on, otherwise 1). Weeks follow
//    the calendar's first weekday. The current week is open until it ends.
//
//  Days are compared as local calendar days (Julian day numbers built from
//  the Gregorian year, month, and day in the calendar's time zone), so
//  daylight-saving changes, 23- and 25-hour days, and non-Gregorian
//  calendars can't shift a day.
//

import Foundation

enum StreakCadence: String, Codable, CaseIterable, Hashable, Sendable {
    case daily
    case weekly
}

struct StreakRules: Codable, Hashable, Sendable {
    var cadence: StreakCadence
    /// Daily streaks only: one missed day in any 7 days doesn't end the streak.
    var allowsGraceDay: Bool
    /// Weekly streaks only: days with an entry a week needs to count, 1...7.
    var weeklyTarget: Int

    init(cadence: StreakCadence = .daily, allowsGraceDay: Bool = true, weeklyTarget: Int = 1) {
        self.cadence = cadence
        self.allowsGraceDay = allowsGraceDay
        self.weeklyTarget = min(7, max(1, weeklyTarget))
    }

    /// Daily, with a grace day: what the app uses until someone changes it.
    static let standard = StreakRules()

    private enum CodingKeys: String, CodingKey {
        case cadence, allowsGraceDay, weeklyTarget
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            cadence: (try? container.decode(StreakCadence.self, forKey: .cadence)) ?? .daily,
            allowsGraceDay: (try? container.decode(Bool.self, forKey: .allowsGraceDay)) ?? true,
            weeklyTarget: (try? container.decode(Int.self, forKey: .weeklyTarget)) ?? 1
        )
    }
}

/// A streak as of one moment.
struct StreakStatus: Equatable, Sendable {
    /// Days with an entry (daily) or weeks that counted (weekly) in the current run.
    var count: Int
    var cadence: StreakCadence
    /// The first local day of the current run; nil when there is no run.
    var runStart: Date?

    static let none = StreakStatus(count: 0, cadence: .daily, runStart: nil)
}

enum JournalStreak {

    // MARK: Dates

    /// The current streak for entries on `entryDates`, as of `now`.
    static func current(
        entryDates: some Sequence<Date>,
        now: Date,
        rules: StreakRules,
        calendar: Calendar = .current
    ) -> StreakStatus {
        let days = dayNumbers(for: entryDates, timeZone: calendar.timeZone)
        let today = dayNumber(for: now, timeZone: calendar.timeZone)
        let run: (count: Int, start: Int?)
        switch rules.cadence {
        case .daily:
            run = currentDailyRun(days: days, today: today, allowsGraceDay: rules.allowsGraceDay)
        case .weekly:
            run = currentWeeklyRun(days: days, today: today, target: rules.weeklyTarget, firstWeekday: calendar.firstWeekday)
        }
        return StreakStatus(
            count: run.count,
            cadence: rules.cadence,
            runStart: run.start.map { date(forDayNumber: $0, timeZone: calendar.timeZone) }
        )
    }

    /// The longest streak ever for entries on `entryDates`.
    static func longest(
        entryDates: some Sequence<Date>,
        rules: StreakRules,
        calendar: Calendar = .current
    ) -> Int {
        let days = dayNumbers(for: entryDates, timeZone: calendar.timeZone)
        switch rules.cadence {
        case .daily:
            return longestDailyRun(days: days, allowsGraceDay: rules.allowsGraceDay)
        case .weekly:
            return longestWeeklyRun(days: days, target: rules.weeklyTarget, firstWeekday: calendar.firstWeekday)
        }
    }

    // MARK: Daily

    /// The run ending at the latest entry on or before `today`.
    static func currentDailyRun(days: Set<Int>, today: Int, allowsGraceDay: Bool) -> (count: Int, start: Int?) {
        guard let latest = days.filter({ $0 <= today }).max() else { return (0, nil) }
        // Days after the latest entry and before today; today itself is still open.
        let trailingMisses = max(0, today - 1 - latest)
        var lastMiss: Int?
        switch trailingMisses {
        case 0:
            break
        case 1 where allowsGraceDay:
            lastMiss = today - 1
        default:
            return (0, nil)
        }

        var count = 1
        var start = latest
        for previous in days.filter({ $0 < latest }).sorted(by: >) {
            let gap = start - previous - 1
            if gap == 0 {
                // Consecutive day.
            } else if gap == 1, allowsGraceDay, lastMiss.map({ $0 - (previous + 1) >= 7 }) ?? true {
                lastMiss = previous + 1
            } else {
                break
            }
            count += 1
            start = previous
        }
        return (count, start)
    }

    /// The longest run of entry days under the daily rules.
    static func longestDailyRun(days: Set<Int>, allowsGraceDay: Bool) -> Int {
        let sorted = days.sorted()
        guard !sorted.isEmpty else { return 0 }
        var best = 1
        var windowStart = 0
        // The most recent missed day inside the window and the index of the entry after it.
        var lastMiss: (day: Int, nextIndex: Int)?

        for index in 1..<sorted.count {
            let gap = sorted[index] - sorted[index - 1] - 1
            if gap == 0 {
                // Consecutive day.
            } else if gap == 1, allowsGraceDay {
                let miss = sorted[index - 1] + 1
                if let previous = lastMiss, miss - previous.day < 7 {
                    // Two misses inside 7 days: the run restarts after the earlier one.
                    windowStart = previous.nextIndex
                }
                lastMiss = (miss, index)
            } else {
                windowStart = index
                lastMiss = nil
            }
            best = max(best, index - windowStart + 1)
        }
        return best
    }

    // MARK: Weekly

    static func currentWeeklyRun(days: Set<Int>, today: Int, target: Int, firstWeekday: Int) -> (count: Int, start: Int?) {
        let counted = countedWeeks(days: days, target: target, firstWeekday: firstWeekday)
        let thisWeek = weekStart(of: today, firstWeekday: firstWeekday)
        // This week is open, so only a week that already counts is part of the run.
        var week = counted.contains(thisWeek) ? thisWeek : thisWeek - 7
        var count = 0
        var start: Int?
        while counted.contains(week) {
            count += 1
            start = week
            week -= 7
        }
        return (count, start)
    }

    static func longestWeeklyRun(days: Set<Int>, target: Int, firstWeekday: Int) -> Int {
        let weeks = countedWeeks(days: days, target: target, firstWeekday: firstWeekday).sorted()
        guard !weeks.isEmpty else { return 0 }
        var best = 1
        var current = 1
        for index in 1..<weeks.count {
            current = weeks[index] - weeks[index - 1] == 7 ? current + 1 : 1
            best = max(best, current)
        }
        return best
    }

    /// Start days of the weeks with at least `target` days with an entry.
    static func countedWeeks(days: Set<Int>, target: Int, firstWeekday: Int) -> Set<Int> {
        var daysPerWeek: [Int: Int] = [:]
        for day in days {
            daysPerWeek[weekStart(of: day, firstWeekday: firstWeekday), default: 0] += 1
        }
        let needed = min(7, max(1, target))
        return Set(daysPerWeek.filter { $0.value >= needed }.keys)
    }

    /// The day number the week containing `day` starts on.
    static func weekStart(of day: Int, firstWeekday: Int) -> Int {
        day - ((weekday(of: day) - firstWeekday + 7) % 7)
    }

    /// Foundation's weekday numbering: 1 is Sunday, 7 is Saturday.
    static func weekday(of day: Int) -> Int {
        ((day + 1) % 7 + 7) % 7 + 1
    }

    // MARK: Day numbers

    static func dayNumbers(for dates: some Sequence<Date>, timeZone: TimeZone) -> Set<Int> {
        let calendar = gregorian(in: timeZone)
        return Set(dates.map { dayNumber(for: $0, calendar: calendar) })
    }

    static func dayNumber(for date: Date, timeZone: TimeZone) -> Int {
        dayNumber(for: date, calendar: gregorian(in: timeZone))
    }

    /// The Julian day number of the local Gregorian date.
    static func julianDayNumber(year: Int, month: Int, day: Int) -> Int {
        let a = (14 - month) / 12
        let y = year + 4800 - a
        let m = month + 12 * a - 3
        return day + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045
    }

    /// Local midnight of the day with Julian day number `number`.
    static func date(forDayNumber number: Int, timeZone: TimeZone) -> Date {
        let a = number + 32044
        let b = (4 * a + 3) / 146097
        let c = a - 146097 * b / 4
        let d = (4 * c + 3) / 1461
        let e = c - 1461 * d / 4
        let m = (5 * e + 2) / 153
        let components = DateComponents(
            year: 100 * b + d - 4800 + m / 10,
            month: m + 3 - 12 * (m / 10),
            day: e - (153 * m + 2) / 5 + 1
        )
        let calendar = gregorian(in: timeZone)
        return calendar.date(from: components).map { calendar.startOfDay(for: $0) } ?? Date(timeIntervalSince1970: 0)
    }

    private static func dayNumber(for date: Date, calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return julianDayNumber(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    private static func gregorian(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}
