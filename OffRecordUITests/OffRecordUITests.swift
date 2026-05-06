//
//  OffRecordUITests.swift
//  OffRecordUITests
//
//  Created by Karthikeyan NG on 01/12/25.
//

import XCTest

final class OffRecordUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    @MainActor
    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            // This measures how long it takes to launch your application.
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }

    @MainActor
    func testDaypartHeroShowsForEmptyToday() throws {
        let app = launchHeroNudgeApp(arguments: ["-HeroNudgeEmptyToday"])

        XCTAssertTrue(app.otherElements["daypartHero.large"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["daypartHero.imageSurface"].firstMatch.waitForExistence(timeout: 4))
        XCTAssertFalse(app.otherElements["daypartHero.compact"].exists)
    }

    @MainActor
    func testDaypartHeroShowsCompactAfterTodayEntry() throws {
        let app = launchHeroNudgeApp(arguments: ["-HeroNudgeHasToday"])

        XCTAssertTrue(app.staticTexts["Today's Entry"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.otherElements["daypartHero.compact"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["daypartHero.imageSurface"].firstMatch.waitForExistence(timeout: 4))
        XCTAssertFalse(app.descendants(matching: .any)["daypartHero.thumbnail"].exists)
    }

    @MainActor
    func testDaypartHeroWelcomeForFirstEntry() throws {
        let app = launchHeroNudgeApp(arguments: ["-HeroNudgeFirstRun"])

        XCTAssertTrue(app.otherElements["daypartHero.welcome"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Welcome to your private diary")).firstMatch.exists)
    }

    @MainActor
    func testDaypartHeroPrimaryCTAEntersRecordingMode() throws {
        let app = launchHeroNudgeApp(arguments: ["-HeroNudgeEmptyToday"])
        XCTAssertTrue(app.otherElements["daypartHero.large"].waitForExistence(timeout: 8))

        addUIInterruptionMonitor(withDescription: "Microphone Permission") { alert in
            let allowButton = alert.buttons["Allow"]
            if allowButton.exists {
                allowButton.tap()
                return true
            }
            return false
        }

        let primaryCTA = app.descendants(matching: .any)["daypartHero.primaryCTA"].firstMatch
        XCTAssertTrue(primaryCTA.waitForExistence(timeout: 4))
        primaryCTA.tap()
        app.tap()

        let recordingMeter = app.descendants(matching: .any)["daypartHero.recordingMeter"].firstMatch
        XCTAssertTrue(recordingMeter.waitForExistence(timeout: 8))
    }

    private func launchHeroNudgeApp(arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-HeroNudgeUITest"] + arguments
        app.launch()
        return app
    }
}
