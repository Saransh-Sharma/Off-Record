import XCTest

/// Month in Review, Year in Review, Session Prep, and Import entry points.
@MainActor
final class ReviewsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private var lastYear: Int { Calendar.current.component(.year, from: Date()) - 1 }

    private var lastMonthKey: String {
        let calendar = Calendar.current
        let lastMonth = calendar.date(byAdding: .month, value: -1, to: Date()) ?? Date()
        let components = calendar.dateComponents([.year, .month], from: lastMonth)
        return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        launchOffRecord(arguments: ["-UITesting", "-ReviewsUITest"] + extra)
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    private func openInsightsCard(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        tapOffRecordTab("insights", in: app)
        let target = element(identifier, in: app)
        scrollClearOfBottomBars(target, in: app, maxSwipes: 14)
        XCTAssertTrue(target.waitForExistence(timeout: 10), "Missing \(identifier)")
        return target
    }

    // MARK: Month in Review

    func testInsightsShowsLastMonthsReviewAndOpensIt() throws {
        let app = launch()
        openInsightsCard("monthInReview.latest", in: app).tap()

        XCTAssertTrue(element("monthInReview.view", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(element("periodReview.cover", in: app).waitForExistence(timeout: 4))
        XCTAssertTrue(element("periodReview.stats", in: app).exists)
        XCTAssertFalse(element("periodReview.support", in: app).exists)
    }

    func testMonthLinkOpensTheReview() throws {
        let app = launch(["-OpenRoute", "offrecord://review/month/\(lastMonthKey)"])
        XCTAssertTrue(element("monthInReview.view", in: app).waitForExistence(timeout: 12))
    }

    func testHighRiskMonthShowsSupport() throws {
        let app = launch(["-ReviewsHighRisk", "-OpenRoute", "offrecord://review/month/\(lastMonthKey)"])
        XCTAssertTrue(element("monthInReview.view", in: app).waitForExistence(timeout: 12))
        let support = element("periodReview.support", in: app)
        XCTAssertTrue(support.waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["getSupport.button"].firstMatch.exists)
    }

    // MARK: Year in Review

    func testYearInReviewOpensFromInsights() throws {
        let app = launch()
        openInsightsCard("yearInReview.row.\(lastYear)", in: app).tap()

        XCTAssertTrue(element("yearInReview.view", in: app).waitForExistence(timeout: 12))
        let pixels = element("yearInReview.pixels", in: app)
        scrollUntilVisible(pixels, in: app, maxSwipes: 4)
        XCTAssertTrue(pixels.exists)
    }

    func testYearLinkOpensTheReviewAndShareShowsAPreview() throws {
        let app = launch(["-OpenRoute", "offrecord://review/year/\(lastYear)"])
        XCTAssertTrue(element("yearInReview.view", in: app).waitForExistence(timeout: 12))

        let share = app.buttons["yearInReview.share"].firstMatch
        scrollUntilVisible(share, in: app, maxSwipes: 12)
        XCTAssertTrue(share.waitForExistence(timeout: 4))
        share.tap()
        XCTAssertTrue(app.buttons["yearInReview.share.confirm"].firstMatch.waitForExistence(timeout: 8))
    }

    func testThisYearsReviewWaitsForDecember() throws {
        let calendar = Calendar.current
        try XCTSkipIf(calendar.component(.month, from: Date()) == 12, "This year's review is open in December.")
        let thisYear = calendar.component(.year, from: Date())
        let app = launch(["-OpenRoute", "offrecord://review/year/\(thisYear)"])
        XCTAssertTrue(element("periodReview.unavailable", in: app).waitForExistence(timeout: 12))
    }

    // MARK: Session Prep

    func testSessionPrepOpensFromInsightsWithNoQuotesPicked() throws {
        let app = launch()
        openInsightsCard("insights.sessionPrep.open", in: app).tap()

        XCTAssertTrue(element("sessionPrep.view", in: app).waitForExistence(timeout: 8))
        XCTAssertTrue(element("sessionPrep.summary", in: app).exists)
        let replaceNames = app.switches["sessionPrep.replaceNames"].firstMatch
        scrollUntilVisible(replaceNames, in: app, maxSwipes: 12)
        XCTAssertEqual(replaceNames.value as? String, "1")
        for toggle in app.switches.matching(identifier: "sessionPrep.quote.toggle").allElementsBoundByIndex {
            XCTAssertEqual(toggle.value as? String, "0")
        }
        XCTAssertTrue(app.buttons["sessionPrep.export"].firstMatch.exists)
    }

    func testSessionPrepOpensFromSettingsExport() throws {
        let app = launch()
        tapOffRecordTab("settings", in: app)
        let export = app.buttons.containingLabel("Backup, text").firstMatch
        scrollUntilVisible(export, in: app, maxSwipes: 10)
        XCTAssertTrue(export.waitForExistence(timeout: 8))
        export.tap()

        let sessionPrep = element("export.sessionPrep.open", in: app)
        scrollUntilVisible(sessionPrep, in: app, maxSwipes: 8)
        XCTAssertTrue(sessionPrep.waitForExistence(timeout: 8))
        sessionPrep.tap()
        XCTAssertTrue(element("sessionPrep.view", in: app).waitForExistence(timeout: 8))
    }

    // MARK: Import

    func testImportOpensFromSettings() throws {
        let app = launch()
        tapOffRecordTab("settings", in: app)
        let open = element("settings.import.open", in: app)
        scrollUntilVisible(open, in: app, maxSwipes: 10)
        XCTAssertTrue(open.waitForExistence(timeout: 8))
        open.tap()

        XCTAssertTrue(element("import.source.dayOne", in: app).waitForExistence(timeout: 8))
        XCTAssertTrue(element("import.source.appleJournal", in: app).exists)
        XCTAssertTrue(element("import.source.markdown", in: app).exists)
        XCTAssertTrue(element("import.source.csv", in: app).exists)
    }
}
