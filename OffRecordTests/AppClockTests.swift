import Foundation
import Testing
@testable import OffRecord

/// The UI-test clock override and the week-aware Weekly Reflection fixtures.
@MainActor
struct AppClockTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }

    @Test func parsesThePinnedInstant() {
        let pinned = AppClock.pinnedDate(in: ["OffRecord", "-UITesting", "-UITestNow", "2026-05-27T12:00:00Z"])
        #expect(pinned == ISO8601DateFormatter().date(from: "2026-05-27T12:00:00Z"))
    }

    @Test func ignoresAMissingOrMalformedInstant() {
        #expect(AppClock.pinnedDate(in: ["OffRecord", "-UITestNow"]) == nil)
        #expect(AppClock.pinnedDate(in: ["OffRecord", "-UITestNow", "next Wednesday"]) == nil)
        #expect(AppClock.pinnedDate(in: ["OffRecord", "-UITesting"]) == nil)
    }

    @Test func unitTestsRunOnTheRealClock() {
        // The test host launches without -UITestNow, so production behavior applies.
        #expect(abs(AppClock.now.timeIntervalSinceNow) < 1)
    }

    @Test(arguments: [
        "2026-05-25T19:00:00Z", // Monday
        "2026-05-26T19:00:00Z", // Tuesday
        "2026-05-27T19:00:00Z", // Wednesday
        "2026-05-31T19:00:00Z", // Sunday
        "2026-03-08T19:00:00Z", // Sunday of the spring-forward change
        "2026-03-09T19:00:00Z", // Monday after it
        "2026-11-01T20:00:00Z", // Sunday of the fall-back change
        "2026-11-02T20:00:00Z"  // Monday after it
    ])
    func weeklyFixturesStayInsideTheWeekUnderTest(instant: String) throws {
        let now = try #require(ISO8601DateFormatter().date(from: instant))
        let period = WeeklyReflectionEligibilityService.period(containing: now, calendar: calendar)

        let dates = UITestDataSeeder.weeklyFixtureDates(count: 3, now: now, calendar: calendar)

        #expect(dates.count == 3)
        #expect(dates.allSatisfy(period.contains))
        #expect(Set(dates.map { calendar.startOfDay(for: $0) }).count == 3)
        #expect(calendar.isDate(dates[0], inSameDayAs: now))
    }

    @Test func weeklyFixturesWalkBackFromMidweek() throws {
        let wednesday = try #require(ISO8601DateFormatter().date(from: "2026-05-27T19:00:00Z"))

        let dates = UITestDataSeeder.weeklyFixtureDates(count: 3, now: wednesday, calendar: calendar)

        #expect(dates.map { calendar.component(.weekday, from: $0) } == [4, 3, 2])
    }
}
