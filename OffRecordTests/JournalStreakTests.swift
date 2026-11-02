import Foundation
import Testing
@testable import OffRecord

/// Streak math shared by the app and the widgets (`JournalStreak`).
struct JournalStreakTests {
    private static let losAngeles = TimeZone(identifier: "America/Los_Angeles")!

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.losAngeles
        calendar.firstWeekday = 2
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    /// Entry dates for every day of May 2026 except `missing`.
    private func may(except missing: Set<Int> = [], through lastDay: Int) -> [Date] {
        (1...lastDay).filter { !missing.contains($0) }.map { date(2026, 5, $0, hour: 9) }
    }

    private let daily = StreakRules(cadence: .daily, allowsGraceDay: false)
    private let dailyWithGrace = StreakRules(cadence: .daily, allowsGraceDay: true)

    private func current(_ dates: [Date], now: Date, _ rules: StreakRules) -> Int {
        JournalStreak.current(entryDates: dates, now: now, rules: rules, calendar: calendar).count
    }

    // MARK: Daily

    @Test func countsConsecutiveDaysEndingTodayOrYesterday() {
        let dates = may(through: 10)
        #expect(current(dates, now: date(2026, 5, 10, hour: 20), daily) == 10)
        // Today is still open: no entry yet doesn't end the streak.
        #expect(current(dates, now: date(2026, 5, 11, hour: 8), daily) == 10)
        #expect(current(dates, now: date(2026, 5, 12, hour: 8), daily) == 0)
    }

    @Test func graceDayKeepsAStreakWithYesterdayMissed() {
        let dates = may(through: 10)
        let twoDaysLater = date(2026, 5, 12, hour: 8)

        #expect(current(dates, now: twoDaysLater, dailyWithGrace) == 10)
        #expect(current(dates, now: twoDaysLater, daily) == 0)
        // Two missed days in a row end it either way.
        #expect(current(dates, now: date(2026, 5, 13, hour: 8), dailyWithGrace) == 0)
    }

    @Test func graceDayCountsOnlyDaysWithAnEntry() {
        let dates = may(except: [5], through: 10)
        let now = date(2026, 5, 10, hour: 20)

        #expect(current(dates, now: now, dailyWithGrace) == 9)
        #expect(current(dates, now: now, daily) == 5)
    }

    @Test func twoMissesInsideSevenDaysEndTheStreak() {
        // Misses on the 4th and the 7th are 3 days apart: the run starts after the 4th.
        let dates = may(except: [4, 7], through: 10)
        let status = JournalStreak.current(entryDates: dates, now: date(2026, 5, 10, hour: 20), rules: dailyWithGrace, calendar: calendar)

        #expect(status.count == 5)
        #expect(status.runStart == calendar.startOfDay(for: date(2026, 5, 5)))
    }

    @Test func missesSevenDaysApartKeepTheStreak() {
        let dates = may(except: [3, 10], through: 14)
        #expect(current(dates, now: date(2026, 5, 14, hour: 20), dailyWithGrace) == 12)

        // Misses 6 days apart: the run goes back to the 5th, the day after the earlier miss.
        let sixApart = may(except: [4, 10], through: 14)
        #expect(current(sixApart, now: date(2026, 5, 14, hour: 20), dailyWithGrace) == 9)
    }

    @Test func trailingMissCountsTowardTheWeeklyAllowance() {
        // Missed the 8th, wrote the 9th, missed yesterday (the 10th): two misses 2 days apart,
        // so only the 9th is left in the run.
        let dates = may(except: [8], through: 9)
        #expect(current(dates, now: date(2026, 5, 11, hour: 8), dailyWithGrace) == 1)
        #expect(current(dates, now: date(2026, 5, 10, hour: 8), dailyWithGrace) == 8)
    }

    @Test func longestRunRestartsRightAfterAnEarlierMiss() {
        // Runs: 1–3, miss 4, 5–6, miss 7, 8–20. The best window starts on the 5th.
        let dates = may(except: [4, 7], through: 20)

        #expect(JournalStreak.longest(entryDates: dates, rules: dailyWithGrace, calendar: calendar) == 15)
        #expect(JournalStreak.longest(entryDates: dates, rules: daily, calendar: calendar) == 13)
        #expect(JournalStreak.longest(entryDates: [], rules: dailyWithGrace, calendar: calendar) == 0)
    }

    @Test func longestRunIsNeverShorterThanTheCurrentOne() {
        let dates = may(except: [2, 9, 16], through: 22)
        let now = date(2026, 5, 24, hour: 8)

        let currentCount = current(dates, now: now, dailyWithGrace)
        let longest = JournalStreak.longest(entryDates: dates, rules: dailyWithGrace, calendar: calendar)
        #expect(currentCount == 19)
        #expect(longest >= currentCount)
    }

    // MARK: Calendar edges

    @Test func springForwardDayDoesntBreakAStreak() {
        // 2026-03-08 has 23 hours in Los Angeles.
        let dates = [date(2026, 3, 7, hour: 23), date(2026, 3, 8, hour: 0), date(2026, 3, 8, hour: 23), date(2026, 3, 9, hour: 0)]
        #expect(current(dates, now: date(2026, 3, 9, hour: 12), daily) == 3)
    }

    @Test func fallBackDayDoesntCountTwice() {
        // 2026-11-01 has 25 hours; 1 AM happens twice.
        let first = date(2026, 11, 1, hour: 1)
        let repeated = first.addingTimeInterval(3_600)
        let dates = [date(2026, 10, 31, hour: 22), first, repeated, date(2026, 11, 1, hour: 23), date(2026, 11, 2, hour: 0)]

        #expect(calendar.isDate(first, inSameDayAs: repeated))
        #expect(current(dates, now: date(2026, 11, 2, hour: 12), daily) == 3)
    }

    @Test func yearBoundaryAndLeapDayAreConsecutive() {
        #expect(current([date(2025, 12, 31), date(2026, 1, 1)], now: date(2026, 1, 1), daily) == 2)
        #expect(current([date(2028, 2, 28), date(2028, 2, 29), date(2028, 3, 1)], now: date(2028, 3, 1), daily) == 3)
    }

    @Test func dayNumbersRoundTrip() {
        let start = date(2026, 3, 8)
        #expect(JournalStreak.julianDayNumber(year: 2000, month: 1, day: 1) == 2_451_545)
        #expect(JournalStreak.weekday(of: 2_451_545) == 7) // Saturday
        for offset in 0..<400 {
            let day = calendar.date(byAdding: .day, value: offset, to: start)!
            let number = JournalStreak.dayNumber(for: day, timeZone: Self.losAngeles)
            #expect(JournalStreak.date(forDayNumber: number, timeZone: Self.losAngeles) == calendar.startOfDay(for: day))
        }
    }

    @Test func nonGregorianCalendarsCountTheSameDays() {
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = Self.losAngeles
        let dates = may(except: [5], through: 10)
        let now = date(2026, 5, 10, hour: 20)

        #expect(JournalStreak.current(entryDates: dates, now: now, rules: dailyWithGrace, calendar: buddhist).count == 9)
    }

    // MARK: Weekly

    @Test func weeklyStreakCountsWeeksThatMetTheTarget() {
        // Weeks start on Monday: May 4, 11, 18, 25.
        let dates = [date(2026, 5, 5), date(2026, 5, 13), date(2026, 5, 14), date(2026, 5, 19), date(2026, 5, 21)]
        let now = date(2026, 5, 26)

        // This week is open: it has no entry yet, so the run ends last week.
        #expect(current(dates, now: now, StreakRules(cadence: .weekly, weeklyTarget: 1)) == 3)
        #expect(current(dates, now: now, StreakRules(cadence: .weekly, weeklyTarget: 2)) == 2)
        #expect(current(dates + [date(2026, 5, 26)], now: now, StreakRules(cadence: .weekly, weeklyTarget: 1)) == 4)
        #expect(current(dates, now: date(2026, 6, 2), StreakRules(cadence: .weekly, weeklyTarget: 1)) == 0)
    }

    @Test func weeklyStreakCrossesTheYearBoundary() {
        let dates = [date(2025, 12, 23), date(2025, 12, 30), date(2026, 1, 6)]
        #expect(current(dates, now: date(2026, 1, 8), StreakRules(cadence: .weekly)) == 3)
        #expect(JournalStreak.longest(entryDates: dates + [date(2026, 1, 27)], rules: StreakRules(cadence: .weekly), calendar: calendar) == 3)
    }

    @Test func weeksFollowTheCalendarsFirstWeekday() {
        // Sunday May 10 and Monday May 11 share a week only when weeks start on Sunday.
        var sundayFirst = calendar
        sundayFirst.firstWeekday = 1
        let dates = [date(2026, 5, 10), date(2026, 5, 11)]
        let rules = StreakRules(cadence: .weekly, weeklyTarget: 2)

        #expect(JournalStreak.current(entryDates: dates, now: date(2026, 5, 12), rules: rules, calendar: sundayFirst).count == 1)
        #expect(JournalStreak.current(entryDates: dates, now: date(2026, 5, 12), rules: rules, calendar: calendar).count == 0)
    }

    // MARK: Rules and widgets

    @Test func rulesDecodeWithDefaultsAndClampTheTarget() throws {
        let decoded = try JSONDecoder().decode(StreakRules.self, from: Data(#"{"cadence":"weekly"}"#.utf8))
        #expect(decoded == StreakRules(cadence: .weekly, allowsGraceDay: true, weeklyTarget: 1))
        #expect(StreakRules(cadence: .weekly, weeklyTarget: 12).weeklyTarget == 7)
        #expect(StreakRules.standard == StreakRules(cadence: .daily, allowsGraceDay: true, weeklyTarget: 1))
    }

    @Test func weeklyStreakUsesTheGoalOnlyWhileItIsOn() {
        #expect(GoalManager.streakRules(cadence: .weekly, allowsGraceDay: true, goalEnabled: true, weeklyTarget: 4).weeklyTarget == 4)
        #expect(GoalManager.streakRules(cadence: .weekly, allowsGraceDay: true, goalEnabled: false, weeklyTarget: 4).weeklyTarget == 1)
    }

    @Test func olderWidgetSnapshotsDecodeWithTheStandardRules() throws {
        let json = #"{"version":1,"days":{"2026-05-10":"calm"},"totalEntries":1,"todayKey":null,"todayWordCount":0,"todayHasVoice":false}"#
        let snapshot = try JSONDecoder().decode(WidgetSnapshot.self, from: Data(json.utf8))

        #expect(snapshot.streakRules == nil)
        #expect(snapshot.effectiveStreakRules == .standard)
    }

    @Test(arguments: [
        StreakRules(cadence: .daily, allowsGraceDay: false),
        StreakRules(cadence: .daily, allowsGraceDay: true),
        StreakRules(cadence: .weekly, weeklyTarget: 1),
        StreakRules(cadence: .weekly, weeklyTarget: 3)
    ])
    func widgetShowsTheSameStreakAsTheApp(rules: StreakRules) async {
        let calendar = Calendar.current
        let now = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: Date())!
        // Two gaps, so each rule set gives a different number.
        let offsets = [0, 1, 2, 4, 5, 6, 7, 8, 9, 12, 13, 14, 15, 16, 20, 21, 22, 23]
        let dates = offsets.map { calendar.date(byAdding: .day, value: -$0, to: now)! }
        let snapshots = dates.enumerated().map { index, date in
            JournalEntrySnapshot(
                id: "entry-\(index)", uuid: UUID(), objectIDURI: "memory://\(index)", date: date,
                text: "A few words", mood: .calm, wordCount: 3, duration: 0,
                isStarred: false, hasAudio: false, photoCount: 0
            )
        }

        let stats = await JournalAnalyticsWorker.shared.makeStats(
            from: snapshots, now: now, weeklyTarget: rules.weeklyTarget, goalEnabled: true, streakRules: rules
        )
        let widget = WidgetSnapshot(
            days: Dictionary(uniqueKeysWithValues: dates.map { (WidgetDayKey.key(for: $0, calendar: calendar), "calm") }),
            totalEntries: dates.count,
            todayKey: WidgetDayKey.key(for: now, calendar: calendar),
            todayWordCount: 3,
            todayHasVoice: false,
            streakRules: rules
        )

        #expect(widget.streak(asOf: now, calendar: calendar) == stats.currentStreak)
        #expect(stats.streakRules == rules)
        // The widget's timeline also renders tomorrow, before the app runs again.
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        #expect(widget.streak(asOf: tomorrow, calendar: calendar)
            == JournalStreak.current(entryDates: dates, now: tomorrow, rules: rules, calendar: calendar).count)
    }

    @Test func streakCopyNeverFramesALoss() {
        let copy = [
            StreakCopy.label(count: 5, cadence: .daily), StreakCopy.label(count: 2, cadence: .weekly),
            StreakCopy.sentence(count: 7, cadence: .daily), StreakCopy.soFar(count: 3, cadence: .weekly),
            StreakCopy.rationale(for: .standard), StreakCopy.rationale(for: StreakRules(cadence: .weekly, weeklyTarget: 3))
        ].joined(separator: " ").lowercased()

        for word in ["lose", "lost", "break", "broken", "miss out", "don’t", "keep it up"] {
            #expect(!copy.contains(word))
        }
        #expect(StreakCopy.label(count: 5, cadence: .daily) == "5-day streak")
        #expect(StreakCopy.duration(count: 1, cadence: .weekly) == "1 week")
    }
}
