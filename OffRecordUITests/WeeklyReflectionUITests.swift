import XCTest

@MainActor
final class WeeklyReflectionUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testHomeOpensWeeklyReflectionReport() throws {
        let app = launchWeeklyReflectionApp()
        tapTab("today", in: app)

        let ready = app.descendants(matching: .any)["weeklyReflection.home.ready"].firstMatch
        scrollUntilExists(ready, in: app)
        XCTAssertTrue(ready.waitForExistence(timeout: 8))
        if ready.frame.maxY > app.frame.height - 180 {
            app.swipeUp()
        }
        ready.tap()

        XCTAssertTrue(app.descendants(matching: .any)["weeklyReflection.report.cover"].firstMatch.waitForExistence(timeout: 6))
    }

    func testEmptyFailedAndDismissedHomeStates() throws {
        let emptyApp = launchWeeklyReflectionApp("-WeeklyReflectionEmpty")
        tapTab("today", in: emptyApp)
        let empty = emptyApp.descendants(matching: .any)["weeklyReflection.home.empty"].firstMatch
        scrollUntilExists(empty, in: emptyApp)
        XCTAssertTrue(empty.waitForExistence(timeout: 8))

        let failedApp = launchWeeklyReflectionApp("-WeeklyReflectionFailed")
        tapTab("today", in: failedApp)
        let failed = failedApp.descendants(matching: .any)["weeklyReflection.home.failed"].firstMatch
        scrollUntilExists(failed, in: failedApp)
        XCTAssertTrue(failed.waitForExistence(timeout: 8))

        let dismissedApp = launchWeeklyReflectionApp("-WeeklyReflectionDismissed")
        tapTab("today", in: dismissedApp)
        XCTAssertFalse(dismissedApp.descendants(matching: .any)["weeklyReflection.home.ready"].firstMatch.waitForExistence(timeout: 2))
    }

    func testHighRiskReportShowsSupportCard() throws {
        let app = launchWeeklyReflectionApp("-WeeklyReflectionHighRisk")
        tapTab("today", in: app)

        let ready = app.descendants(matching: .any)["weeklyReflection.home.ready"].firstMatch
        scrollUntilExists(ready, in: app)
        XCTAssertTrue(ready.waitForExistence(timeout: 8))
        if ready.frame.maxY > app.frame.height - 180 {
            app.swipeUp()
        }
        ready.tap()

        XCTAssertTrue(app.staticTexts["Support"].firstMatch.waitForExistence(timeout: 6))
    }

    func testSourceSheetOpensEntryAndCanUpdateInclusion() throws {
        let app = launchWeeklyReflectionApp()
        tapTab("today", in: app)

        let ready = app.descendants(matching: .any)["weeklyReflection.home.ready"].firstMatch
        scrollUntilExists(ready, in: app)
        XCTAssertTrue(ready.waitForExistence(timeout: 8))
        if ready.frame.maxY > app.frame.height - 180 {
            app.swipeUp()
        }
        ready.tap()
        XCTAssertTrue(app.descendants(matching: .any)["weeklyReflection.report.cover"].firstMatch.waitForExistence(timeout: 6))

        let sources = app.buttons["weeklyReflection.sources.openSheet"].firstMatch
        scrollUntilExists(sources, in: app)
        XCTAssertTrue(sources.waitForExistence(timeout: 6))
        sources.tap()

        let includeToggle = app.descendants(matching: .any)["weeklyReflection.sources.includeToggle"].firstMatch
        scrollUntilExists(includeToggle, in: app, maxSwipes: 4)
        XCTAssertTrue(includeToggle.waitForExistence(timeout: 6))
        includeToggle.tap()
        let update = app.buttons["weeklyReflection.sources.update"].firstMatch
        XCTAssertTrue(update.waitForExistence(timeout: 4))
        XCTAssertTrue(update.isEnabled)
        update.tap()
    }

    func testSettingsShowsWeeklyReflectionControls() throws {
        let app = launchWeeklyReflectionApp()
        tapTab("settings", in: app)

        let toggle = app.switches["weeklyReflection.settings.enabled"].firstMatch
        scrollUntilExists(toggle, in: app)
        XCTAssertTrue(toggle.waitForExistence(timeout: 8))
    }

    private func launchWeeklyReflectionApp(_ extraArguments: String...) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-UITesting",
            "-WeeklyReflectionUITest"
        ] + extraArguments
        app.launch()
        XCTAssertTrue(app.buttons["tab.today"].firstMatch.waitForExistence(timeout: 10))
        return app
    }

    private func tapTab(_ id: String, in app: XCUIApplication) {
        let tab = app.buttons["tab.\(id)"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 8))
        tab.tap()
    }

    private func scrollUntilExists(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 8) {
        guard !element.exists else { return }
        for _ in 0..<maxSwipes where !element.exists {
            app.swipeUp()
        }
    }
}
