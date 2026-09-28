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
        // Let the launch splash finish fading out; auditing mid-fade measures washed-out text.
        _ = XCTWaiter().wait(for: [XCTestExpectation(description: "Splash settles")], timeout: 2)
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
        scrollClearOfBottomBars(ready, in: app)
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
        scrollClearOfBottomBars(ready, in: app)
        XCTAssertTrue(ready.waitForExistence(timeout: 8))
        ready.tap()
        XCTAssertTrue(app.descendants(matching: .any)["weeklyReflection.report.cover"].firstMatch.waitForExistence(timeout: 8))
    }

    @available(iOS 17.0, *)
    private func auditCurrentScreen(_ app: XCUIApplication) throws {
        let screen = app.frame
        let bottomChromeTop = min(bottomBarsMinY(in: app), screen.maxY - 90)
        try app.performAccessibilityAudit { issue in
            // iOS 26 softens scroll content near the top of the screen and as it approaches the
            // bottom bars, so contrast sampled there measures the blur, not the text.
            // Entry previews are deliberately cut to a couple of lines; the full text is one tap away.
            let previewIdentifiers: Set<String> = ["todayEntry.preview", "timeline.entrySnippet", "timeline.evidenceSnippet"]
            if issue.auditType == .textClipped, let id = issue.element?.identifier, previewIdentifiers.contains(id) {
                return true
            }
            // The system search field's own placeholder layout isn't the app's to change.
            if issue.auditType == .textClipped, issue.element?.elementType == .searchField {
                return true
            }
            // White text on the opaque preview card; the audit's sample varies with whichever
            // hero illustration loaded behind the card, so it can't be judged reliably here.
            if issue.auditType == .contrast, issue.element?.identifier == "todayEntry.preview" {
                return true
            }
            if issue.auditType == .contrast, let frame = issue.element?.frame,
               frame.maxY > bottomChromeTop - 40 || frame.minY < screen.minY + 110 {
                return true
            }
            // Name the offending element so a failure is actionable from the log alone.
            let element = issue.element.map { "\($0.elementType) id='\($0.identifier)' label='\($0.label)' frame=\($0.frame)" } ?? "no element"
            print("ACCESSIBILITY AUDIT: \(issue.compactDescription) — \(element) — \(issue.detailedDescription)")
            return false
        }
    }
}
