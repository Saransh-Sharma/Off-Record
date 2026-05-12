//
//  ProactiveReflectionUITests.swift
//  OffRecordUITests
//
//  Focused UI coverage for proactive reflection surfaces.
//

import XCTest

@MainActor
final class ProactiveReflectionUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testFridayShowsProactiveReflectionSection() throws {
        let app = launchProactiveReflectionApp()

        app.buttons["tab.friday"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["proactiveReflection.section"].firstMatch.waitForExistence(timeout: 8))
        let cardPredicate = NSPredicate(format: "identifier BEGINSWITH %@", "proactiveReflection.card.")
        let card = app.descendants(matching: .any).matching(cardPredicate).firstMatch
        scrollUntilExists(card, in: app)
        XCTAssertTrue(card.waitForExistence(timeout: 4))
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        XCTAssertTrue(app.descendants(matching: .any)["proactiveReflection.detail"].firstMatch.waitForExistence(timeout: 4))
        XCTAssertTrue(app.descendants(matching: .any)["proactiveReflection.evidence.source"].firstMatch.waitForExistence(timeout: 4))
    }

    func testTodayShowsContextAwareReflectionPrompt() throws {
        let app = launchProactiveReflectionApp()

        app.buttons["tab.today"].tap()

        let prompt = app.descendants(matching: .any)["proactiveReflection.todayPrompt"].firstMatch
        XCTAssertTrue(prompt.waitForExistence(timeout: 8))
        prompt.tap()
        XCTAssertTrue(app.staticTexts["Writing prompt"].waitForExistence(timeout: 4))
    }

    func testTodayDoesNotShowPromptAfterCurrentDayEntryExists() throws {
        let app = launchProactiveReflectionApp(extraArguments: ["-ProactiveReflectionHasToday"])

        app.buttons["tab.today"].tap()

        let prompt = app.descendants(matching: .any)["proactiveReflection.todayPrompt"].firstMatch
        XCTAssertFalse(prompt.waitForExistence(timeout: 3))
    }

    func testFridayDecisionDetailExposesMarkReflected() throws {
        let app = launchProactiveReflectionApp()

        app.buttons["tab.friday"].tap()

        let decisionCard = app.descendants(matching: .any)["proactiveReflection.card.decision"].firstMatch
        scrollUntilExists(decisionCard, in: app)
        XCTAssertTrue(decisionCard.waitForExistence(timeout: 6))
        decisionCard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        XCTAssertTrue(app.buttons["proactiveReflection.markReflected"].firstMatch.waitForExistence(timeout: 4))
    }

    func testSettingsShowsSmartReminderToggle() throws {
        let app = launchProactiveReflectionApp()

        app.buttons["tab.settings"].tap()
        let toggle = app.switches["proactiveReflection.smartReminderToggle"].firstMatch
        scrollUntilExists(toggle, in: app)

        XCTAssertTrue(toggle.waitForExistence(timeout: 8))
    }

    private func launchProactiveReflectionApp(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-UITesting",
            "-ProactiveReflectionUITest"
        ] + extraArguments
        app.launch()
        XCTAssertTrue(app.buttons["tab.today"].waitForExistence(timeout: 10))
        return app
    }

    private func scrollUntilExists(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 8) {
        guard !element.exists else { return }
        for _ in 0..<maxSwipes where !element.exists {
            app.swipeUp()
        }
    }
}
