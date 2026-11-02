import Foundation
import Testing
@testable import ReflectionKit

struct ReflectionPeriodTests {

    private func calendar(_ identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0, in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    // MARK: Months

    @Test func monthSpansFirstToLastSecondInLocalTime() {
        let auckland = calendar("Pacific/Auckland")
        let period = ReflectionPeriodCalendar.period(.month, containing: date(2026, 9, 15, in: auckland), calendar: auckland)

        #expect(period.start == date(2026, 9, 1, 0, in: auckland))
        #expect(period.end == date(2026, 10, 1, 0, in: auckland).addingTimeInterval(-1))
        #expect(period.contains(date(2026, 9, 30, 23, 59, in: auckland)))
        #expect(!period.contains(date(2026, 10, 1, 0, in: auckland)))
    }

    @Test func februaryEndsOnTheLeapDayOnlyInLeapYears() {
        let losAngeles = calendar("America/Los_Angeles")
        let leap = ReflectionPeriodCalendar.month(year: 2028, month: 2, calendar: losAngeles)!
        let common = ReflectionPeriodCalendar.month(year: 2027, month: 2, calendar: losAngeles)!

        #expect(losAngeles.component(.day, from: leap.end) == 29)
        #expect(losAngeles.component(.day, from: common.end) == 28)
        #expect(leap.contains(date(2028, 2, 29, 22, in: losAngeles)))
    }

    @Test func monthsAcrossDaylightSavingChangesStayWhole() {
        let losAngeles = calendar("America/Los_Angeles")
        // DST starts March 8, 2026 and ends November 1, 2026 in Los Angeles.
        let march = ReflectionPeriodCalendar.month(year: 2026, month: 3, calendar: losAngeles)!
        let november = ReflectionPeriodCalendar.month(year: 2026, month: 11, calendar: losAngeles)!

        #expect(losAngeles.component(.hour, from: march.start) == 0)
        #expect(losAngeles.component(.hour, from: march.end.addingTimeInterval(1)) == 0)
        #expect(losAngeles.component(.day, from: november.end) == 30)
        #expect(losAngeles.component(.hour, from: november.end) == 23)
    }

    @Test func januaryLooksBackToThePreviousDecember() {
        let auckland = calendar("Pacific/Auckland")
        let last = ReflectionPeriodCalendar.lastCompletedPeriod(.month, before: date(2027, 1, 3, in: auckland), calendar: auckland)

        #expect(ReflectionPeriodCalendar.key(for: last, kind: .month, calendar: auckland) == "2026-12")
        #expect(last.start == date(2026, 12, 1, 0, in: auckland))
    }

    @Test func completedMonthsAreNewestFirstWithoutGaps() {
        let utc = calendar("UTC")
        let months = ReflectionPeriodCalendar.completedPeriods(.month, before: date(2026, 3, 10, in: utc), count: 4, calendar: utc)
        let keys = months.map { ReflectionPeriodCalendar.key(for: $0, kind: .month, calendar: utc) }

        #expect(keys == ["2026-02", "2026-01", "2025-12", "2025-11"])
    }

    @Test func outOfRangeMonthsAndYearsAreRejected() {
        #expect(ReflectionPeriodCalendar.month(year: 2026, month: 13) == nil)
        #expect(ReflectionPeriodCalendar.month(year: 2026, month: 0) == nil)
        #expect(ReflectionPeriodCalendar.year(0) == nil)
        #expect(ReflectionPeriodCalendar.year(10_000) == nil)
    }

    // MARK: Years

    @Test func leapYearHas366Days() {
        let utc = calendar("UTC")
        let leap = ReflectionPeriodCalendar.year(2028, calendar: utc)!
        let common = ReflectionPeriodCalendar.year(2027, calendar: utc)!
        let leapDays = utc.dateComponents([.day], from: leap.start, to: leap.end.addingTimeInterval(1)).day
        let commonDays = utc.dateComponents([.day], from: common.start, to: common.end.addingTimeInterval(1)).day

        #expect(leapDays == 366)
        #expect(commonDays == 365)
        #expect(ReflectionPeriodCalendar.key(for: leap, kind: .year, calendar: utc) == "2028")
    }

    @Test func yearInReviewOpensOnDecemberFirstInLocalTime() {
        let losAngeles = calendar("America/Los_Angeles")
        // 2026-12-01 06:00 UTC is still November 30 in Los Angeles.
        let utcDecemberFirst = ISO8601DateFormatter().date(from: "2026-12-01T06:00:00Z")!
        #expect(!ReflectionPeriodCalendar.isYearInReviewAvailable(year: 2026, now: utcDecemberFirst, hasEntries: true, calendar: losAngeles))

        let localDecemberFirst = date(2026, 12, 1, 0, 1, in: losAngeles)
        #expect(ReflectionPeriodCalendar.isYearInReviewAvailable(year: 2026, now: localDecemberFirst, hasEntries: true, calendar: losAngeles))
        #expect(ReflectionPeriodCalendar.isYearInReviewAvailable(year: 2026, now: date(2026, 12, 31, 23, in: losAngeles), hasEntries: true, calendar: losAngeles))
    }

    @Test func pastYearsNeedEntriesAndFutureYearsNeverOpen() {
        let utc = calendar("UTC")
        let october = date(2026, 10, 1, in: utc)

        #expect(ReflectionPeriodCalendar.isYearInReviewAvailable(year: 2025, now: october, hasEntries: true, calendar: utc))
        #expect(!ReflectionPeriodCalendar.isYearInReviewAvailable(year: 2025, now: october, hasEntries: false, calendar: utc))
        #expect(!ReflectionPeriodCalendar.isYearInReviewAvailable(year: 2026, now: october, hasEntries: true, calendar: utc))
        #expect(!ReflectionPeriodCalendar.isYearInReviewAvailable(year: 2027, now: date(2026, 12, 15, in: utc), hasEntries: true, calendar: utc))
    }

    // MARK: Weeks

    @Test func weekStartsMondayAndEndsSundayNight() {
        let utc = calendar("UTC")
        // Thursday, January 1, 2026 belongs to ISO week 1, which starts Monday, December 29, 2025.
        let week = ReflectionPeriodCalendar.period(.week, containing: date(2026, 1, 1, in: utc), calendar: utc)

        #expect(week.start == date(2025, 12, 29, 0, in: utc))
        #expect(week.end == date(2026, 1, 5, 0, in: utc).addingTimeInterval(-1))
        #expect(ReflectionPeriodCalendar.key(for: week, kind: .week, calendar: utc) == "2026-W01")
    }

    // MARK: Eligibility

    private func snapshots(count: Int, wordsEach: Int, from start: Date, calendar: Calendar) -> [WeeklyReflectionEntrySnapshot] {
        (0..<count).map { index in
            let day = calendar.date(byAdding: .day, value: index, to: start)!
            return WeeklyReflectionEntrySnapshot(
                id: UUID(),
                date: day,
                updatedAt: day,
                mood: nil,
                text: Array(repeating: "word", count: wordsEach).joined(separator: " "),
                sourceType: .text
            )
        }
    }

    @Test func weekKindMatchesTheShippedWeeklyEngine() {
        let utc = calendar("UTC")
        let week = ReflectionPeriodCalendar.period(.week, containing: date(2026, 9, 23, in: utc), calendar: utc)
        for (count, words) in [(1, 100), (2, 80), (2, 400), (3, 60), (1, 700)] {
            let entries = snapshots(count: count, wordsEach: words, from: week.start.addingTimeInterval(3_600), calendar: utc)
            #expect(
                WeeklyReflectionEligibilityEngine.evaluate(entries: entries, in: week, kind: .week)
                    == WeeklyReflectionEligibilityEngine.evaluate(entries: entries, in: week)
            )
        }
    }

    @Test func monthNeedsFourEntriesAndFullNeedsEight() {
        let utc = calendar("UTC")
        let month = ReflectionPeriodCalendar.month(year: 2026, month: 9, calendar: utc)!
        let start = month.start.addingTimeInterval(3_600)

        #expect(WeeklyReflectionEligibilityEngine.evaluate(entries: snapshots(count: 3, wordsEach: 300, from: start, calendar: utc), in: month, kind: .month).kind == .empty)
        #expect(WeeklyReflectionEligibilityEngine.evaluate(entries: snapshots(count: 4, wordsEach: 60, from: start, calendar: utc), in: month, kind: .month).kind == .light)
        #expect(WeeklyReflectionEligibilityEngine.evaluate(entries: snapshots(count: 8, wordsEach: 30, from: start, calendar: utc), in: month, kind: .month).kind == .full)
        #expect(WeeklyReflectionEligibilityEngine.evaluate(entries: snapshots(count: 4, wordsEach: 500, from: start, calendar: utc), in: month, kind: .month).kind == .full)
    }

    @Test func entriesOutsideThePeriodDoNotCount() {
        let utc = calendar("UTC")
        let month = ReflectionPeriodCalendar.month(year: 2026, month: 9, calendar: utc)!
        let august = snapshots(count: 10, wordsEach: 100, from: date(2026, 8, 1, in: utc), calendar: utc)

        let result = WeeklyReflectionEligibilityEngine.evaluate(entries: august, in: month, kind: .month)
        #expect(result.kind == .empty)
        #expect(result.entryCount == 0)
    }

    // MARK: Storage

    @Test func periodReviewRoundTripsThroughJSON() throws {
        let utc = calendar("UTC")
        let period = ReflectionPeriodCalendar.month(year: 2026, month: 9, calendar: utc)!
        let report = WeeklyReflectionReport(
            id: UUID(), periodStart: period.start, periodEnd: period.end, generatedAt: period.end,
            versionNumber: 1, processingMode: .local, status: .ready, eligibility: .full,
            includedEntryIds: [UUID()], hiddenEntryIds: [], unavailableEntryIds: [], privateEntryCount: 0,
            inputSignature: "sig", heroSentence: "Hero.", summary: "Summary.", emotionalArc: nil,
            themes: [], wins: [], frictions: [], questions: [], savedTakeaway: nil,
            safetyLevel: .none, userMarkedHelpful: nil
        )
        var stats = PeriodReviewStats.empty
        stats.entryCount = 12
        stats.recordedSeconds = 610
        stats.topPeople = [PeriodReviewMention(nodeID: "maya", label: "Maya", entryCount: 4)]
        let review = PeriodReview(kind: .month, periodKey: "2026-09", report: report, stats: stats)

        let decoded = try JSONDecoder().decode(PeriodReview.self, from: JSONEncoder().encode(review))

        #expect(decoded == review)
        #expect(decoded.stats.recordedMinutes == 10)
        #expect(!decoded.touchesHighRiskContent)
    }
}
