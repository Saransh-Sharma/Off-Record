import XCTest

@MainActor
final class CaptureFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTodayWriteNoteCreatesEntryAcrossTodayTimelineAndDetail() throws {
        let app = launchCaptureApp()
        let entryText = "UI test text capture stays private and searchable."

        saveTextEntry(entryText, byTapping: app.buttons["todayDock.write"].firstMatch, in: app)

        app.buttons["entryDetail.backButton"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["homeHero.todayEntryPreview"].firstMatch.waitForExistence(timeout: 8))

        tapOffRecordTab("timeline", in: app)
        searchTimeline(for: "UI test text capture", in: app)
        XCTAssertTrue(app.staticTexts.containingLabel(entryText).firstMatch.waitForExistence(timeout: 8))

        app.staticTexts.containingLabel(entryText).firstMatch.tap()
        let detailText = app.staticTexts["entryDetail.mainText"].firstMatch
        XCTAssertTrue(detailText.waitForExistence(timeout: 8))
        XCTAssertTrue(detailText.label.localizedCaseInsensitiveContains(entryText))
    }

    func testPromptEntryCreatesPersistedStartedEntry() throws {
        let app = launchCaptureApp()
        let entryText = "UI test prompted reflection becomes a saved journal entry."
        let nudge = app.descendants(matching: .any)["today.nudge.0"].firstMatch
        scrollUntilVisible(nudge, in: app, maxSwipes: 5)

        saveTextEntry(entryText, byTapping: nudge, in: app)

        XCTAssertTrue(app.staticTexts["entryDetail.mainText"].firstMatch.waitForExistence(timeout: 8))
        app.buttons["entryDetail.backButton"].firstMatch.tap()
        tapOffRecordTab("timeline", in: app)
        searchTimeline(for: "prompted reflection", in: app)
        XCTAssertTrue(app.staticTexts.containingLabel(entryText).firstMatch.waitForExistence(timeout: 8))
    }

    func testRecordingCTAStartsAndStopsSafelyInDeterministicFixture() throws {
        let app = launchCaptureApp()
        let recordButton = app.descendants(matching: .any)["todayDock.record"].firstMatch
        XCTAssertTrue(recordButton.waitForExistence(timeout: 8))

        recordButton.tap()
        let panel = app.descendants(matching: .any)["capture.panel"].firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 8))

        let save = app.buttons["capture.save"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 4))
        save.tap()
        XCTAssertTrue(waitForElementToDisappear(panel, timeout: 5))
        XCTAssertTrue(recordButton.waitForExistence(timeout: 4))
        XCTAssertEqual(recordButton.label, "Start recording")
    }

    func testRecordingWithoutSpeechConsentShowsDisclosureAfterLocalSave() throws {
        let app = launchCaptureApp(extraArguments: ["-CaptureSpeechConsentUITest"])
        let recordButton = app.descendants(matching: .any)["todayDock.record"].firstMatch
        XCTAssertTrue(recordButton.waitForExistence(timeout: 8))

        recordButton.tap()
        XCTAssertTrue(app.descendants(matching: .any)["capture.panel"].firstMatch.waitForExistence(timeout: 8))
        app.buttons["capture.save"].firstMatch.tap()

        XCTAssertTrue(app.alerts["On-Device Transcription"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.alerts.buttons["Transcribe on Device"].exists)
        XCTAssertTrue(app.alerts.buttons["Not Now"].exists)
        app.alerts.buttons["Not Now"].tap()

        // The recording is still saved even without transcription.
        XCTAssertTrue(app.descendants(matching: .any)["capture.saved"].firstMatch.waitForExistence(timeout: 4))
    }

    func testSavedCaptureOffersQuickMoodAndUndo() throws {
        let app = launchCaptureApp(extraArguments: ["-CaptureSpeechConsentUITest"])
        app.descendants(matching: .any)["todayDock.record"].firstMatch.tap()
        XCTAssertTrue(app.buttons["capture.save"].firstMatch.waitForExistence(timeout: 8))
        app.buttons["capture.save"].firstMatch.tap()
        if app.alerts["On-Device Transcription"].waitForExistence(timeout: 4) {
            app.alerts.buttons["Not Now"].tap()
        }

        let calm = app.buttons["capture.mood.calm"].firstMatch
        XCTAssertTrue(calm.waitForExistence(timeout: 4))
        calm.tap()
        XCTAssertTrue(calm.isSelected)

        app.buttons["Undo"].firstMatch.tap()
        XCTAssertTrue(waitForElementToDisappear(app.descendants(matching: .any)["capture.saved"].firstMatch, timeout: 4))
    }

    private func launchCaptureApp(extraArguments: [String] = []) -> XCUIApplication {
        launchOffRecord(arguments: [
            "-UITesting",
            "-HeroNudgeUITest",
            "-hasCompletedOnboarding",
            "YES"
        ] + extraArguments)
    }

    private func saveTextEntry(_ text: String, byTapping opener: XCUIElement, in app: XCUIApplication) {
        scrollUntilVisible(opener, in: app, maxSwipes: 5)
        XCTAssertTrue(opener.waitForExistence(timeout: 8))
        opener.tap()

        let editor = app.textViews["entryDetail.newTextBlock"].firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 8))
        editor.tap()
        editor.typeText(text)

        let save = app.buttons["entryDetail.saveText"].firstMatch
        XCTAssertTrue(waitForElement(save, matching: NSPredicate(format: "isEnabled == true"), timeout: 4))
        save.tap()
        XCTAssertTrue(app.staticTexts["entryDetail.mainText"].firstMatch.waitForExistence(timeout: 8))
    }

    private func searchTimeline(for query: String, in app: XCUIApplication) {
        let searchField = app.searchFields["timeline.searchField"].firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 8))
        searchField.tap()
        searchField.typeText(query)
    }
}
