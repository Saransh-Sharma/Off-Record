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

    func testEmptyHomeState() throws {
        let emptyApp = launchWeeklyReflectionApp("-WeeklyReflectionEmpty")
        tapTab("today", in: emptyApp)
        let empty = emptyApp.descendants(matching: .any)["weeklyReflection.home.empty"].firstMatch
        scrollUntilExists(empty, in: emptyApp)
        XCTAssertTrue(empty.waitForExistence(timeout: 8))
    }

    func testFailedHomeState() throws {
        let failedApp = launchWeeklyReflectionApp("-WeeklyReflectionFailed")
        tapTab("today", in: failedApp)
        let failed = failedApp.descendants(matching: .any)["weeklyReflection.home.failed"].firstMatch
        scrollUntilExists(failed, in: failedApp)
        XCTAssertTrue(failed.waitForExistence(timeout: 8))
    }

    func testDismissedHomeStateHidesReadyCard() throws {
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

        XCTAssertTrue(app.descendants(matching: .any)["weeklyReflection.support"].firstMatch.waitForExistence(timeout: 6))
    }

    func testLightReportOpensWithTwoIncludedEntries() throws {
        let app = launchWeeklyReflectionApp("-WeeklyReflectionLight")
        openCurrentReportFromToday(in: app)

        XCTAssertTrue(app.descendants(matching: .any)["weeklyReflection.report.cover"].firstMatch.waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts.matching(labelContaining: "2 entries included").firstMatch.waitForExistence(timeout: 4))
    }

    func testSourceSheetOpensEntryAndCanUpdateInclusion() throws {
        let app = launchWeeklyReflectionApp()
        openReportFromInsightsHistory(in: app)

        openSourcesSheetFromReportMenu(in: app)

        let includeToggle = app.switches["weeklyReflection.sources.includeToggle"].firstMatch
        scrollUntilHittable(includeToggle, in: app, maxSwipes: 10)
        XCTAssertTrue(includeToggle.waitForExistence(timeout: 6))
        let originalValue = includeToggle.value as? String
        includeToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(includeToggle.waitForValueChange(from: originalValue, timeout: 3))
    }

    func testSourceSheetOpenEntryNavigatesToEntry() throws {
        let app = launchWeeklyReflectionApp()
        openReportFromInsightsHistory(in: app)

        openSourcesSheetFromReportMenu(in: app)

        let sourceButton = app.buttons["weeklyReflection.sources.openEntry"].firstMatch
        scrollUntilHittable(sourceButton, in: app, maxSwipes: 10)
        XCTAssertTrue(sourceButton.waitForExistence(timeout: 6))
        sourceButton.tap()
        XCTAssertTrue(app.staticTexts["entryDetail.mainText"].firstMatch.waitForExistence(timeout: 6))
    }

    func testSettingsShowsWeeklyReflectionControls() throws {
        let app = launchWeeklyReflectionApp()
        tapTab("settings", in: app)

        let toggle = app.switches["weeklyReflection.settings.enabled"].firstMatch
        scrollUntilExists(toggle, in: app)
        XCTAssertTrue(toggle.waitForExistence(timeout: 8))
    }

    func testInsightsHistoryRowOpensSavedReport() throws {
        let app = launchWeeklyReflectionApp()
        tapTab("insights", in: app)

        let row = app.descendants(matching: .any)["weeklyReflection.history.row"].firstMatch
        scrollUntilExists(row, in: app, maxSwipes: 8)
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        row.tap()

        XCTAssertTrue(app.descendants(matching: .any)["weeklyReflection.report.cover"].firstMatch.waitForExistence(timeout: 6))
    }

    func testSaveTakeawayPersistsAfterReopeningReport() throws {
        let app = launchWeeklyReflectionApp()
        let takeaway = "Carry the quiet boundary forward."

        openCurrentReportFromToday(in: app)
        saveTakeaway(takeaway, in: app)
        app.navigationBars.buttons.firstMatch.tap()

        openCurrentReportFromToday(in: app)
        let field = app.textFields["weeklyReflection.takeaway.textField"].firstMatch
        scrollUntilExists(field, in: app, maxSwipes: 8)
        XCTAssertTrue(field.waitForExistence(timeout: 6))
        XCTAssertTrue((field.value as? String ?? "").localizedCaseInsensitiveContains(takeaway))
    }

    func testDismissHidesHomeCardButPreservesHistory() throws {
        let app = launchWeeklyReflectionApp()
        openCurrentReportFromToday(in: app)

        openReportMenu(in: app)
        app.buttons["Dismiss this week"].firstMatch.tap()

        tapTab("today", in: app)
        XCTAssertFalse(app.descendants(matching: .any)["weeklyReflection.home.ready"].firstMatch.waitForExistence(timeout: 2))

        tapTab("insights", in: app)
        let row = app.descendants(matching: .any)["weeklyReflection.history.row"].firstMatch
        scrollUntilExists(row, in: app, maxSwipes: 8)
        XCTAssertTrue(row.waitForExistence(timeout: 8))
    }

    func testDeletedReportIsHiddenFromHistory() throws {
        let app = launchWeeklyReflectionApp("-WeeklyReflectionDeleted")
        tapTab("insights", in: app)
        XCTAssertFalse(app.descendants(matching: .any)["weeklyReflection.history.row"].firstMatch.waitForExistence(timeout: 3))
    }

    func testExportSheetExposesFormatAndQuoteControls() throws {
        let app = launchWeeklyReflectionApp()
        openCurrentReportFromToday(in: app)

        let export = app.buttons["weeklyReflection.export.open"].firstMatch
        scrollUntilExists(export, in: app, maxSwipes: 8)
        XCTAssertTrue(export.waitForExistence(timeout: 6))
        export.tap()

        XCTAssertTrue(app.navigationBars["Export Reflection"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.switches["weeklyReflection.export.includeQuotes"].firstMatch.exists)
        XCTAssertTrue(app.buttons["weeklyReflection.export.preview"].firstMatch.exists)
        XCTAssertTrue(app.pickers["weeklyReflection.export.format"].firstMatch.exists || app.buttons["weeklyReflection.export.format"].firstMatch.exists)
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

    private func openCurrentReportFromToday(in app: XCUIApplication) {
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

    private func openReportFromInsightsHistory(in app: XCUIApplication) {
        tapTab("insights", in: app)
        let row = app.descendants(matching: .any)["weeklyReflection.history.row"].firstMatch
        scrollUntilExists(row, in: app, maxSwipes: 8)
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["weeklyReflection.report.cover"].firstMatch.waitForExistence(timeout: 6))
    }

    private func saveTakeaway(_ text: String, in app: XCUIApplication) {
        let field = app.textFields["weeklyReflection.takeaway.textField"].firstMatch
        scrollUntilExists(field, in: app, maxSwipes: 8)
        XCTAssertTrue(field.waitForExistence(timeout: 6))
        field.tap()
        field.typeText(text)

        let save = app.buttons["weeklyReflection.takeaway.save"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 4))
        save.tap()
    }

    private func openReportMenu(in app: XCUIApplication) {
        let menu = app.buttons["weeklyReflection.report.menu"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 6))
        menu.tap()
    }

    private func openSourcesSheetFromReportMenu(in app: XCUIApplication) {
        openReportMenu(in: app)
        let menuItem = app.buttons["Privacy & sources"].firstMatch
        XCTAssertTrue(menuItem.waitForExistence(timeout: 4))
        menuItem.tap()
        XCTAssertTrue(app.navigationBars["Privacy & Sources"].waitForExistence(timeout: 6))
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

    private func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 8) {
        for _ in 0..<maxSwipes where !element.exists || !element.isHittable {
            app.swipeUp()
        }
    }
}

private extension XCUIElementQuery {
    func matching(labelContaining text: String) -> XCUIElementQuery {
        matching(NSPredicate(format: "label CONTAINS[c] %@", text))
    }
}

private extension XCUIElement {
    func waitForValueChange(from originalValue: String?, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate { element, _ in
            guard let element = element as? XCUIElement else { return false }
            return element.value as? String != originalValue
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
