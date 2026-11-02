import XCTest

/// Keep Out of Friday on an entry, the Friday switch in Settings, and Erase All Data.
@MainActor
final class PrivacyControlsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testKeepOutOfFridayFromTheEntryMenu() throws {
        let app = launchOffRecord(arguments: ["-UITesting", "-HeroNudgeHasToday"])
        turnFridayOnIfNeeded(in: app)
        openFirstTimelineEntry(in: app)

        XCTAssertTrue(app.descendants(matching: .any)["entryDetail.goDeeper"].firstMatch.waitForExistence(timeout: 8))
        let note = app.descendants(matching: .any)["entryDetail.keptOutNote"].firstMatch
        XCTAssertFalse(note.exists)

        tapMenuItem("entryDetail.keepOutOfFriday", label: "Keep Out of Friday", in: app)
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        XCTAssertTrue(note.label.contains("Friday won’t read or quote this entry."))
        XCTAssertTrue(waitForElementToDisappear(app.descendants(matching: .any)["entryDetail.goDeeper"].firstMatch))

        tapMenuItem("entryDetail.skipWeeklyReflection", label: "Skip Weekly Reflection", in: app)
        XCTAssertTrue(waitForElement(note, matching: NSPredicate(format: "label CONTAINS %@", "Weekly Reflection")))

        tapMenuItem("entryDetail.keepOutOfFriday", label: "Keep Out of Friday", in: app)
        XCTAssertTrue(waitForElementToDisappear(note))
        XCTAssertTrue(app.descendants(matching: .any)["entryDetail.goDeeper"].firstMatch.waitForExistence(timeout: 5))
    }

    func testTurningFridayOffShowsHerOffState() throws {
        let app = launchOffRecord(arguments: ["-UITesting"])
        turnFridayOnIfNeeded(in: app)

        tapOffRecordTab("settings", in: app)
        let toggle = app.switches["settings.friday.toggle"].firstMatch
        scrollUntilVisible(toggle, in: app)
        XCTAssertTrue(toggle.waitForExistence(timeout: 8))
        XCTAssertEqual(toggle.value as? String, "1")
        flip(toggle)

        let alert = app.alerts["Turn Off Friday?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Turn Off"].tap()
        XCTAssertTrue(waitForElement(toggle, matching: NSPredicate(format: "value == '0'")))

        tapOffRecordTab("friday", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["friday.off"].firstMatch.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["friday.talk"].firstMatch.exists)

        app.buttons["friday.off.turnOn"].firstMatch.tap()
        XCTAssertTrue(app.buttons["friday.talk"].firstMatch.waitForExistence(timeout: 8))
    }

    func testFridayRouteLandsOnTheOffState() throws {
        var app = launchOffRecord(arguments: ["-UITesting"])
        turnFridayOnIfNeeded(in: app)
        setFriday(on: false, in: app)
        app.terminate()

        app = launchOffRecord(arguments: ["-UITesting", "-OpenRoute", "offrecord://friday?question=How%20was%20my%20week"])
        XCTAssertTrue(app.descendants(matching: .any)["friday.off"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.textFields["friday.askField"].firstMatch.exists)

        app.buttons["friday.off.turnOn"].firstMatch.tap()
        XCTAssertTrue(app.buttons["friday.talk"].firstMatch.waitForExistence(timeout: 8))
    }

    func testEraseAllDataLandsOnAFreshToday() throws {
        let app = launchOffRecord(arguments: ["-UITesting", "-HeroNudgeHasToday"])
        XCTAssertFalse(app.descendants(matching: .any)["today.firstEntry"].firstMatch.exists)

        tapOffRecordTab("settings", in: app)
        let erase = app.buttons["settings.eraseAllData"].firstMatch
        scrollUntilVisible(erase, in: app, maxSwipes: 14)
        XCTAssertTrue(erase.waitForExistence(timeout: 8))
        erase.tap()

        let first = app.alerts["Erase All Data?"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(first.staticTexts.containingLabel("Every entry, recording, and photo").firstMatch.exists)
        first.buttons["Continue"].tap()

        let second = app.alerts["This Can’t Be Undone"]
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        second.buttons["Erase All Data"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["today.firstEntry"].firstMatch.waitForExistence(timeout: 15))
        tapOffRecordTab("timeline", in: app)
        XCTAssertFalse(entryRows(in: app).firstMatch.waitForExistence(timeout: 3))
    }

    // MARK: Helpers

    private func entryRows(in app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'timeline.entryRow'"))
    }

    private func openFirstTimelineEntry(in app: XCUIApplication) {
        tapOffRecordTab("timeline", in: app)
        let row = entryRows(in: app).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        row.tap()
        XCTAssertTrue(app.buttons["More"].firstMatch.waitForExistence(timeout: 8))
    }

    private func tapMenuItem(_ identifier: String, label: String, in app: XCUIApplication) {
        app.buttons["More"].firstMatch.tap()
        let byID = app.descendants(matching: .any)[identifier].firstMatch
        let item = byID.waitForExistence(timeout: 3) ? byID : app.buttons[label].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "Missing menu item \(label)")
        item.tap()
    }

    /// Taps the switch itself; tapping the label doesn't flip a toggle.
    private func flip(_ toggle: XCUIElement) {
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
    }

    /// Settings persist between launches, so a failed run must not leave Friday off for the next test.
    private func turnFridayOnIfNeeded(in app: XCUIApplication) {
        tapOffRecordTab("friday", in: app)
        let turnOn = app.buttons["friday.off.turnOn"].firstMatch
        if turnOn.waitForExistence(timeout: 2) {
            turnOn.tap()
            XCTAssertTrue(app.buttons["friday.talk"].firstMatch.waitForExistence(timeout: 8))
        }
        tapOffRecordTab("today", in: app)
    }

    private func setFriday(on: Bool, in app: XCUIApplication) {
        tapOffRecordTab("settings", in: app)
        let toggle = app.switches["settings.friday.toggle"].firstMatch
        scrollUntilVisible(toggle, in: app)
        XCTAssertTrue(toggle.waitForExistence(timeout: 8))
        guard (toggle.value as? String == "1") != on else { return }
        flip(toggle)
        if !on {
            let alert = app.alerts["Turn Off Friday?"]
            XCTAssertTrue(alert.waitForExistence(timeout: 5))
            alert.buttons["Turn Off"].tap()
        }
        XCTAssertTrue(waitForElement(toggle, matching: NSPredicate(format: "value == %@", on ? "1" : "0")))
    }
}
