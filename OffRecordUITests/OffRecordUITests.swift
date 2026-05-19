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
    func testOnboardingFirstEntryCTAStaysVisibleWhenKeyboardAppears() throws {
        let app = launchOnboardingApp(arguments: ["-OnboardingFirstEntryTextUITest"])
        let entryField = app.descendants(matching: .any)["onboarding.firstEntry.textField"].firstMatch

        XCTAssertTrue(entryField.waitForExistence(timeout: 8))
        XCTAssertTrue(entryField.isHittable)

        entryField.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 4))
        entryField.typeText("Today I need to say this honestly.")

        let saveButton = app.buttons["Save entry"].firstMatch
        XCTAssertTrue(saveButton.waitForExistence(timeout: 4))
        XCTAssertTrue(saveButton.isHittable)

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "OnboardingFirstEntryKeyboardVisible"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testOnboardingFirstEntryVoiceStateHasNoTypeInsteadButton() throws {
        let app = launchOnboardingApp(arguments: ["-OnboardingFirstEntryVoiceUITest"])

        XCTAssertTrue(app.staticTexts["Start with one honest thought"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Record privately"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["Skip first entry"].firstMatch.exists)
        XCTAssertFalse(app.buttons["Type instead"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["onboarding.firstEntry.textField"].exists)
    }

    @MainActor
    func testOnboardingCompletesThroughEightStepSkipPath() throws {
        let app = launchOnboardingApp()

        XCTAssertTrue(app.staticTexts["Your private voice journal"].waitForExistence(timeout: 8))
        attachScreenshot(named: "OnboardingWelcome", app: app)
        app.buttons["Continue"].firstMatch.tap()

        XCTAssertTrue(app.staticTexts["What brings you here?"].waitForExistence(timeout: 4))
        app.buttons["Clear my head"].firstMatch.tap()
        app.buttons["Continue"].firstMatch.tap()

        XCTAssertTrue(app.staticTexts["Private by design"].waitForExistence(timeout: 4))
        app.buttons["Continue"].firstMatch.tap()

        XCTAssertTrue(app.staticTexts["Lock your journal"].waitForExistence(timeout: 4))
        app.buttons["Not now"].firstMatch.tap()

        XCTAssertTrue(app.staticTexts["Tune Friday"].waitForExistence(timeout: 4))
        app.buttons["Emotions"].firstMatch.tap()
        app.buttons["Gentle check-ins"].firstMatch.tap()
        app.buttons["Continue"].firstMatch.tap()

        XCTAssertTrue(app.staticTexts["Start with one honest thought"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.buttons["Type instead"].exists)
        XCTAssertTrue(app.buttons["Skip first entry"].firstMatch.exists)
        app.buttons["Skip first entry"].firstMatch.tap()

        XCTAssertTrue(app.staticTexts["Your first snapshot is ready"].waitForExistence(timeout: 4))
        attachScreenshot(named: "OnboardingSnapshot", app: app)
        app.buttons["Continue"].firstMatch.tap()

        XCTAssertTrue(app.staticTexts["Make reflection easy to repeat"].waitForExistence(timeout: 4))
        attachScreenshot(named: "OnboardingHabit", app: app)
        app.buttons["Enter OffRecord"].firstMatch.tap()

        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 8) || app.buttons["Today"].firstMatch.waitForExistence(timeout: 8))
    }

    @MainActor
    func testTimelineSearchKeyboardKeepsBottomTabsUsable() throws {
        let app = launchSeededApp()
        navigateToTab("Timeline", in: app)

        let searchField = app.searchFields["timeline.searchField"].firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 8))
        searchField.tap()

        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 4))

        let insightsTab = app.buttons["tab.insights"].firstMatch
        XCTAssertTrue(insightsTab.waitForExistence(timeout: 4))
        XCTAssertTrue(insightsTab.isHittable)

        insightsTab.tap()
        XCTAssertTrue(app.navigationBars["Insights"].waitForExistence(timeout: 4))

        let keyboardGone = NSPredicate(format: "exists == false")
        expectation(for: keyboardGone, evaluatedWith: app.keyboards.firstMatch)
        waitForExpectations(timeout: 3)
    }

    @MainActor
    func testSettingsExposeSiriAndSystemSearchControls() throws {
        let app = launchSeededApp()
        navigateToTab("Settings", in: app)

        let section = app.descendants(matching: .any)["settings.systemSearch.section"].firstMatch
        scrollUntilExists(section, in: app)

        XCTAssertTrue(section.waitForExistence(timeout: 5))
        let spotlightToggle = app.switches["settings.systemSearch.spotlightToggle"].firstMatch
        scrollUntilExists(spotlightToggle, in: app)
        XCTAssertTrue(spotlightToggle.exists)

        let rebuildButton = app.buttons["settings.systemSearch.rebuildSpotlight"].firstMatch
        scrollUntilExists(rebuildButton, in: app)
        XCTAssertTrue(rebuildButton.exists)
    }

    @MainActor
    func testDaypartHeroShowsForEmptyToday() throws {
        let app = launchHeroNudgeApp(arguments: ["-HeroNudgeEmptyToday"])

        XCTAssertTrue(app.otherElements["homeHero.fullBleed"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["daypartHero.imageSurface"].firstMatch.waitForExistence(timeout: 4))
        XCTAssertFalse(app.otherElements["homeHero.todayEntryPreview"].exists)
    }

    @MainActor
    func testDaypartHeroShowsEntryPreviewAfterTodayEntry() throws {
        let app = launchHeroNudgeApp(arguments: ["-HeroNudgeHasToday"])

        XCTAssertTrue(app.otherElements["homeHero.fullBleed"].waitForExistence(timeout: 8))
        let entryPreview = app.descendants(matching: .any)["homeHero.todayEntryPreview"].firstMatch
        XCTAssertTrue(entryPreview.waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["daypartHero.imageSurface"].firstMatch.waitForExistence(timeout: 4))
        let nudgeSection = app.descendants(matching: .any)["today.nudgeSection"].firstMatch
        XCTAssertTrue(nudgeSection.waitForExistence(timeout: 4))
        XCTAssertGreaterThanOrEqual(nudgeSection.frame.minY, entryPreview.frame.maxY + 24)

        XCTAssertFalse(app.descendants(matching: .any)["daypartHero.primaryCTA"].firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any)["daypartHero.writeCTA"].firstMatch.exists)
        let dockRecord = app.descendants(matching: .any)["todayDock.record"].firstMatch
        XCTAssertTrue(dockRecord.waitForExistence(timeout: 4))
        XCTAssertLessThanOrEqual(entryPreview.frame.maxY + 12, dockRecord.frame.minY)
        XCTAssertTrue(app.descendants(matching: .any)["todayDock.write"].firstMatch.exists)
    }

    @MainActor
    func testDaypartHeroWelcomeForFirstEntry() throws {
        let app = launchHeroNudgeApp(arguments: ["-HeroNudgeFirstRun"])

        XCTAssertTrue(app.otherElements["homeHero.fullBleed"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["homeHero.timeChip"].firstMatch.waitForExistence(timeout: 4))
    }

    @MainActor
    func testBottomDockShowsRecordingAndWriteCTAs() throws {
        let app = launchHeroNudgeApp(arguments: ["-HeroNudgeEmptyToday"])
        XCTAssertTrue(app.otherElements["homeHero.fullBleed"].waitForExistence(timeout: 8))

        let primaryCTA = app.descendants(matching: .any)["todayDock.record"].firstMatch
        let writeCTA = app.descendants(matching: .any)["todayDock.write"].firstMatch

        XCTAssertTrue(primaryCTA.waitForExistence(timeout: 4))
        XCTAssertEqual(primaryCTA.label, "Start recording")
        XCTAssertTrue(writeCTA.exists)
        XCTAssertEqual(writeCTA.label, "Write note")
        XCTAssertFalse(app.descendants(matching: .any)["daypartHero.primaryCTA"].firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any)["daypartHero.writeCTA"].firstMatch.exists)
    }

    @MainActor
    func testBottomDockPrimaryCTAEntersRecordingMode() throws {
        let app = launchHeroNudgeApp(arguments: ["-HeroNudgeEmptyToday"])
        XCTAssertTrue(app.otherElements["homeHero.fullBleed"].waitForExistence(timeout: 8))

        addUIInterruptionMonitor(withDescription: "Microphone Permission") { alert in
            let allowButton = alert.buttons["Allow"]
            if allowButton.exists {
                allowButton.tap()
                return true
            }
            return false
        }

        let primaryCTA = app.descendants(matching: .any)["todayDock.record"].firstMatch
        XCTAssertTrue(primaryCTA.waitForExistence(timeout: 4))
        primaryCTA.tap()

        let recordingMeter = app.descendants(matching: .any)["daypartHero.recordingMeter"].firstMatch
        XCTAssertTrue(recordingMeter.waitForExistence(timeout: 8))
    }

    @MainActor
    func testEntryStateBottomDockRecordCTAEntersRecordingMode() throws {
        let app = launchHeroNudgeApp(arguments: ["-HeroNudgeHasToday"])
        XCTAssertTrue(app.otherElements["homeHero.fullBleed"].waitForExistence(timeout: 8))

        addUIInterruptionMonitor(withDescription: "Microphone Permission") { alert in
            let allowButton = alert.buttons["Allow"]
            if allowButton.exists {
                allowButton.tap()
                return true
            }
            return false
        }

        let recordCTA = app.descendants(matching: .any)["todayDock.record"].firstMatch
        XCTAssertTrue(recordCTA.waitForExistence(timeout: 4))
        recordCTA.tap()

        let recordingMeter = app.descendants(matching: .any)["daypartHero.recordingMeter"].firstMatch
        XCTAssertTrue(recordingMeter.waitForExistence(timeout: 8))
    }

    @MainActor
    func testNudgeCardOpensComposerWithPrompt() throws {
        let app = launchHeroNudgeApp(arguments: ["-HeroNudgeEmptyToday"])
        XCTAssertTrue(app.otherElements["homeHero.fullBleed"].waitForExistence(timeout: 8))

        let nudge = app.descendants(matching: .any)["today.nudge.0"].firstMatch
        scrollUntilExists(nudge, in: app, maxSwipes: 3)
        for _ in 0..<5 where nudge.exists && !nudge.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(nudge.waitForExistence(timeout: 4))
        XCTAssertTrue(nudge.isHittable)
        nudge.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.18)).tap()

        XCTAssertTrue(app.staticTexts["Writing prompt"].waitForExistence(timeout: 6))
    }

    @MainActor
    func testNudgeRailShowsAllDefaultPrompts() throws {
        let app = launchHeroNudgeApp(arguments: ["-HeroNudgeEmptyToday"])
        XCTAssertTrue(app.otherElements["homeHero.fullBleed"].waitForExistence(timeout: 8))

        for index in 0..<6 {
            let nudge = app.descendants(matching: .any)["today.nudge.\(index)"].firstMatch
            XCTAssertTrue(nudge.waitForExistence(timeout: 4), "Missing nudge card \(index)")
        }
    }

    @MainActor
    func testMoodDialReplacesListAndCancelDoesNotPersist() throws {
        let app = launchSeededApp()
        navigateToTab("Timeline", in: app)
        openSeededCherryBlossomEntry(in: app)

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

    @MainActor
    func testMoodDialDragAndDonePersistsSelection() throws {
        let app = launchSeededApp()
        navigateToTab("Timeline", in: app)
        openSeededCherryBlossomEntry(in: app)

        let moodButton = app.buttons["entryDetail.moodButton"].firstMatch
        XCTAssertTrue(moodButton.waitForExistence(timeout: 6))
        let originalMoodLabel = moodButton.label
        moodButton.tap()

        let wheel = app.otherElements["moodDial.wheel"].firstMatch
        XCTAssertTrue(wheel.waitForExistence(timeout: 4))
        wheel.coordinate(withNormalizedOffset: CGVector(dx: 0.84, dy: 0.78))
            .press(forDuration: 0.1, thenDragTo: wheel.coordinate(withNormalizedOffset: CGVector(dx: 0.16, dy: 0.78)))

        let doneButton = app.buttons["moodDial.done"].firstMatch
        XCTAssertTrue(doneButton.waitForExistence(timeout: 4))
        doneButton.tap()

        XCTAssertTrue(moodButton.waitForExistence(timeout: 4))
        XCTAssertNotEqual(moodButton.label, originalMoodLabel)
    }

    private func launchOnboardingApp() -> XCUIApplication {
        launchOnboardingApp(arguments: [])
    }

    private func launchOnboardingApp(arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-OnboardingUITest"] + arguments
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

    private func attachScreenshot(named name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func openSeededCherryBlossomEntry(in app: XCUIApplication) {
        let firstEntry = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "cherry blossoms")).firstMatch
        if firstEntry.waitForExistence(timeout: 5) {
            firstEntry.tap()
            return
        }

        let fallbackEntry = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "cherry blossoms")).firstMatch
        XCTAssertTrue(fallbackEntry.waitForExistence(timeout: 5))
        fallbackEntry.tap()
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

    private func scrollUntilExists(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 8) {
        guard !element.exists else { return }
        for _ in 0..<maxSwipes where !element.exists {
            app.swipeUp()
        }
    }
}
