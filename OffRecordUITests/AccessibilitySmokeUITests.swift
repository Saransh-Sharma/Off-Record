import XCTest

@MainActor
final class AccessibilitySmokeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSeededCoreScreensPassAccessibilityAudit() throws {
        let app = launchOffRecord(arguments: [
            "-UITesting",
            "-ScreenshotMode",
            "-hasCompletedOnboarding",
            "YES",
            "-AppleLanguages",
            "(en)",
            "-AppleLocale",
            "en_US"
        ])

        XCTAssertTrue(app.otherElements["homeHero.fullBleed"].waitForExistence(timeout: 8))
        try auditCurrentScreen(app)

        tapOffRecordTab("timeline", in: app)
        XCTAssertTrue(app.searchFields["timeline.searchField"].firstMatch.waitForExistence(timeout: 8))
        try auditCurrentScreen(app)

        let entry = app.staticTexts.containingLabel("cherry blossoms").firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 8))
        entry.tap()
        XCTAssertTrue(app.staticTexts["entryDetail.mainText"].firstMatch.waitForExistence(timeout: 8))
        try auditCurrentScreen(app)
        app.buttons["entryDetail.backButton"].firstMatch.tap()

        tapOffRecordTab("friday", in: app)
        XCTAssertTrue(app.buttons["friday.talk"].firstMatch.waitForExistence(timeout: 8))
        try auditCurrentScreen(app)

        tapOffRecordTab("settings", in: app)
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 8))
        try auditCurrentScreen(app)
    }

    func testWeeklyReflectionReportPassesAccessibilityAudit() throws {
        let app = launchOffRecord(arguments: [
            "-UITesting",
            "-WeeklyReflectionUITest"
        ])

        let ready = app.descendants(matching: .any)["weeklyReflection.home.ready"].firstMatch
        scrollUntilVisible(ready, in: app, maxSwipes: 8)
        XCTAssertTrue(ready.waitForExistence(timeout: 8))
        ready.tap()

        XCTAssertTrue(app.descendants(matching: .any)["weeklyReflection.report.cover"].firstMatch.waitForExistence(timeout: 8))
        try auditCurrentScreen(app)
    }

    func testDarkModeCoreTabsRemainReachable() throws {
        let app = launchOffRecord(arguments: [
            "-UITesting",
            "-HeroNudgeUITest",
            "-HeroNudgeEmptyToday",
            "-UIUserInterfaceStyle",
            "Dark"
        ])

        XCTAssertTrue(app.otherElements["homeHero.fullBleed"].waitForExistence(timeout: 8))
        for tab in ["timeline", "insights", "friday", "settings", "today"] {
            tapOffRecordTab(tab, in: app)
        }
        XCTAssertTrue(app.descendants(matching: .any)["todayDock.record"].firstMatch.waitForExistence(timeout: 8))
    }

    func testLargeDynamicTypeKeepsTodayFridayAndWeeklyReflectionUsable() throws {
        let app = launchOffRecord(arguments: [
            "-UITesting",
            "-WeeklyReflectionUITest",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryXXXL"
        ])

        XCTAssertTrue(app.descendants(matching: .any)["todayDock.record"].firstMatch.waitForExistence(timeout: 8))
        tapOffRecordTab("friday", in: app)
        let talk = app.buttons["friday.talk"].firstMatch
        scrollUntilVisible(talk, in: app, maxSwipes: 4)
        XCTAssertTrue(talk.waitForExistence(timeout: 8))

        tapOffRecordTab("today", in: app)
        let ready = app.descendants(matching: .any)["weeklyReflection.home.ready"].firstMatch
        scrollUntilVisible(ready, in: app, maxSwipes: 8)
        XCTAssertTrue(ready.waitForExistence(timeout: 8))
        ready.tap()
        XCTAssertTrue(app.descendants(matching: .any)["weeklyReflection.report.cover"].firstMatch.waitForExistence(timeout: 8))
    }

    @available(iOS 17.0, *)
    private func auditCurrentScreen(_ app: XCUIApplication) throws {
        try app.performAccessibilityAudit()
    }
}
