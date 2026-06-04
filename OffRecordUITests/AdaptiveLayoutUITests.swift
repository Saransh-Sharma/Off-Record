import XCTest

@MainActor
final class AdaptiveLayoutUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "-UITesting",
            "-ScreenshotMode",
            "-hasCompletedOnboarding",
            "YES",
            "-AppleLanguages",
            "(en)",
            "-AppleLocale",
            "en_US"
        ]
        app.launch()
    }

    func testRegularWidthTimelineKeepsListVisibleWhenEntryIsSelected() throws {
        navigateToTab("Timeline")
        XCTAssertTrue(app.searchFields["timeline.searchField"].firstMatch.waitForExistence(timeout: 8))

        let firstEntry = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "cherry blossoms")).firstMatch
        XCTAssertTrue(firstEntry.waitForExistence(timeout: 8))
        firstEntry.tap()

        XCTAssertTrue(app.staticTexts["entryDetail.mainText"].firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(
            app.searchFields["timeline.searchField"].firstMatch.exists,
            "Regular-width Timeline should keep the list/search pane visible while showing entry detail."
        )
    }

    func testRegularWidthDoesNotShowCustomFloatingTabBar() throws {
        XCTAssertFalse(
            app.otherElements["offrecord.floatingTabBar"].firstMatch.exists,
            "Regular-width layouts should use system tab/sidebar navigation, not the custom iPhone floating tab bar."
        )
    }

    func testFridayRegularWidthChatKeepsComposerVisible() throws {
        navigateToTab("Friday")
        XCTAssertTrue(app.buttons["friday.talk"].firstMatch.waitForExistence(timeout: 8))
        app.buttons["friday.talk"].firstMatch.tap()

        XCTAssertTrue(app.textFields["friday.askField"].firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(app.otherElements["friday.composer"].firstMatch.exists)
    }

    private func navigateToTab(_ name: String) {
        let customButton = app.buttons["tab.\(name.lowercased())"].firstMatch
        if customButton.waitForExistence(timeout: 2) {
            customButton.tap()
            return
        }

        let nativeTab = app.tabBars.buttons[name].firstMatch
        if nativeTab.waitForExistence(timeout: 2) {
            nativeTab.tap()
            return
        }

        let anyButton = app.buttons[name].firstMatch
        if anyButton.waitForExistence(timeout: 2) {
            anyButton.tap()
            return
        }

        let text = app.staticTexts[name].firstMatch
        if text.waitForExistence(timeout: 2) {
            text.tap()
            return
        }

        XCTFail("Could not find tab: \(name)")
    }
}
