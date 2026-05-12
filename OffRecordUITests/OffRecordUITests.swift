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
    func testOnboardingNameFieldStaysVisibleWhenKeyboardAppears() throws {
        let app = launchOnboardingApp()
        let nameField = app.textFields["onboarding.welcome.nameField"]

        XCTAssertTrue(nameField.waitForExistence(timeout: 8))
        XCTAssertTrue(nameField.isHittable)

        nameField.tap()

        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 4))
        sleep(1)
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertTrue(nameField.isHittable)

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "OnboardingWelcomeKeyboardVisible"
        attachment.lifetime = .keepAlways
        add(attachment)

        nameField.typeText("Saransh")
        XCTAssertEqual(nameField.value as? String, "Saransh")
    }

    @MainActor
    func testOnboardingNameFieldAcceptsTypingAfterTap() throws {
        let app = launchOnboardingApp()
        let nameField = app.textFields["onboarding.welcome.nameField"]

        XCTAssertTrue(nameField.waitForExistence(timeout: 8))
        nameField.tap()
        nameField.typeText("Saransh")

        XCTAssertEqual(nameField.value as? String, "Saransh")
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

        let recordCTA = app.descendants(matching: .any)["daypartHero.compactRecordCTA"].firstMatch
        let writeCTA = app.descendants(matching: .any)["daypartHero.compactCTA"].firstMatch

        XCTAssertTrue(recordCTA.waitForExistence(timeout: 4))
        XCTAssertEqual(recordCTA.label, "Start recording")
        XCTAssertTrue(writeCTA.exists)
        XCTAssertEqual(writeCTA.label, "Write")
    }

    @MainActor
    func testDaypartHeroWelcomeForFirstEntry() throws {
        let app = launchHeroNudgeApp(arguments: ["-HeroNudgeFirstRun"])

        XCTAssertTrue(app.otherElements["daypartHero.welcome"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Welcome to your private diary")).firstMatch.exists)
    }

    @MainActor
    func testDaypartHeroShowsRecordingAndWriteCTAs() throws {
        let app = launchHeroNudgeApp(arguments: ["-HeroNudgeEmptyToday"])
        XCTAssertTrue(app.otherElements["daypartHero.large"].waitForExistence(timeout: 8))

        let primaryCTA = app.descendants(matching: .any)["daypartHero.primaryCTA"].firstMatch
        let writeCTA = app.descendants(matching: .any)["daypartHero.writeCTA"].firstMatch

        XCTAssertTrue(primaryCTA.waitForExistence(timeout: 4))
        XCTAssertEqual(primaryCTA.label, "Start recording")
        XCTAssertTrue(writeCTA.exists)
        XCTAssertEqual(writeCTA.label, "Write")
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

    @MainActor
    func testCompactHeroRecordCTAEntersRecordingMode() throws {
        let app = launchHeroNudgeApp(arguments: ["-HeroNudgeHasToday"])
        XCTAssertTrue(app.otherElements["daypartHero.compact"].waitForExistence(timeout: 8))

        addUIInterruptionMonitor(withDescription: "Microphone Permission") { alert in
            let allowButton = alert.buttons["Allow"]
            if allowButton.exists {
                allowButton.tap()
                return true
            }
            return false
        }

        let recordCTA = app.descendants(matching: .any)["daypartHero.compactRecordCTA"].firstMatch
        XCTAssertTrue(recordCTA.waitForExistence(timeout: 4))
        recordCTA.tap()
        app.tap()

        let recordingMeter = app.descendants(matching: .any)["daypartHero.recordingMeter"].firstMatch
        XCTAssertTrue(recordingMeter.waitForExistence(timeout: 8))
    }

    @MainActor
    func testMoodDialReplacesListAndCancelDoesNotPersist() throws {
        let app = launchSeededApp()
        navigateToTab("Timeline", in: app)

        let firstEntry = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "cherry blossoms")).firstMatch
        if firstEntry.waitForExistence(timeout: 5) {
            firstEntry.tap()
        } else {
            let fallbackEntry = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "cherry blossoms")).firstMatch
            XCTAssertTrue(fallbackEntry.waitForExistence(timeout: 5))
            fallbackEntry.tap()
        }

        let moodButton = app.buttons["entryDetail.moodButton"].firstMatch
        XCTAssertTrue(moodButton.waitForExistence(timeout: 6))
        let originalMoodLabel = moodButton.label
        moodButton.tap()

        XCTAssertTrue(app.otherElements["moodDial.sheet"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.staticTexts["Select a mood"].exists)

        let sentence = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "I feel ")).firstMatch
        XCTAssertTrue(sentence.waitForExistence(timeout: 4))
        let originalSentence = sentence.label

        let wheel = app.otherElements["moodDial.wheel"].firstMatch
        XCTAssertTrue(wheel.waitForExistence(timeout: 4))
        wheel.coordinate(withNormalizedOffset: CGVector(dx: 0.84, dy: 0.78))
            .press(forDuration: 0.1, thenDragTo: wheel.coordinate(withNormalizedOffset: CGVector(dx: 0.16, dy: 0.78)))

        let sentenceChanged = NSPredicate(format: "label != %@", originalSentence)
        expectation(for: sentenceChanged, evaluatedWith: sentence)
        waitForExpectations(timeout: 2)

        app.buttons["moodDial.cancel"].tap()
        XCTAssertTrue(moodButton.waitForExistence(timeout: 4))
        XCTAssertEqual(moodButton.label, originalMoodLabel)
    }

    private func launchOnboardingApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-OnboardingUITest"]
        app.launch()
        return app
    }

    private func launchHeroNudgeApp(arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-HeroNudgeUITest"] + arguments
        app.launch()
        return app
    }

    private func launchSeededApp() -> XCUIApplication {
        let app = XCUIApplication()
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
        return app
    }

    private func navigateToTab(_ name: String, in app: XCUIApplication) {
        let customButton = app.buttons[name].firstMatch
        if customButton.waitForExistence(timeout: 4) {
            customButton.tap()
            return
        }

        let tabButton = app.tabBars.buttons[name]
        if tabButton.waitForExistence(timeout: 4) {
            tabButton.tap()
            return
        }

        XCTFail("Could not find tab: \(name)")
    }
}
