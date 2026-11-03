import Foundation
import Testing
@testable import OffRecord

/// `offrecord://review/year/2026` and `offrecord://review/month/2026-09`.
@MainActor
@Suite(.serialized)
struct ReviewRouteTests {

    @Test func parsesYearAndMonthLinks() {
        #expect(OffRecordNavigationRouter.route(from: URL(string: "offrecord://review/year/2026")!) == .yearInReview(2026))
        #expect(OffRecordNavigationRouter.route(from: URL(string: "offrecord://review/month/2026-09")!) == .monthInReview(year: 2026, month: 9))
        #expect(OffRecordNavigationRouter.route(from: URL(string: "offrecord://review/month/2025-1")!) == .monthInReview(year: 2025, month: 1))
        #expect(OffRecordNavigationRouter.route(from: URL(string: "offrecord://REVIEW/YEAR/2024")!) == .yearInReview(2024))
    }

    @Test func rejectsMalformedLinks() {
        for raw in [
            "offrecord://review",
            "offrecord://review/year",
            "offrecord://review/year/26",
            "offrecord://review/year/0000",
            "offrecord://review/year/twenty",
            "offrecord://review/month/2026-13",
            "offrecord://review/month/2026-00",
            "offrecord://review/month/2026",
            "offrecord://review/month/2026-09-01",
            "offrecord://review/week/2026-W39",
            "offrecord://review/year/2026/extra",
            "https://review/year/2026"
        ] {
            #expect(OffRecordNavigationRouter.route(from: URL(string: raw)!) == nil, "\(raw)")
        }
    }

    @Test func linksRoundTrip() {
        for route: OffRecordRoute in [.yearInReview(2026), .monthInReview(year: 2026, month: 9), .monthInReview(year: 2027, month: 12)] {
            let url = OffRecordNavigationRouter.url(for: route)
            #expect(url.flatMap(OffRecordNavigationRouter.route(from:)) == route)
        }
        #expect(OffRecordNavigationRouter.url(for: .yearInReview(2026))?.absoluteString == "offrecord://review/year/2026")
        #expect(OffRecordNavigationRouter.url(for: .monthInReview(year: 2026, month: 9))?.absoluteString == "offrecord://review/month/2026-09")
    }

    @Test func routingOpensInsightsWithTheReview() {
        let router = OffRecordNavigationRouter.shared
        router.selectedTab = .today
        router.routedReview = nil

        router.route(.monthInReview(year: 2026, month: 9), canNavigate: true)

        #expect(router.selectedTab == .insights)
        #expect(router.routedReview == PeriodReviewRoute(kind: .month, year: 2026, month: 9))

        router.route(.yearInReview(2025), canNavigate: true)
        #expect(router.routedReview == PeriodReviewRoute(kind: .year, year: 2025, month: nil))

        router.routedReview = nil
        router.selectedTab = .today
    }

    @Test func storedReviewLinksWaitUntilTheAppCanNavigate() {
        UserDefaults.standard.removeObject(forKey: OffRecordNavigationRouter.pendingRouteDefaultsKey)
        OffRecordNavigationRouter.storePendingRoute(.yearInReview(2025))
        let router = OffRecordNavigationRouter.shared
        router.routedReview = nil

        router.consumeStoredRoute(canNavigate: false)
        #expect(router.routedReview == nil)

        router.consumeStoredRoute(canNavigate: true)
        #expect(router.routedReview == PeriodReviewRoute(kind: .year, year: 2025, month: nil))
        #expect(UserDefaults.standard.string(forKey: OffRecordNavigationRouter.pendingRouteDefaultsKey) == nil)

        router.routedReview = nil
        router.selectedTab = .today
    }
}
