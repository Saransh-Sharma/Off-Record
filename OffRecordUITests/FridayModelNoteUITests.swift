//
//  FridayModelNoteUITests.swift
//  OffRecordUITests
//
//  Friday's chat says once, in her voice, when Apple Intelligence can't be
//  used. UI tests keep the model off, so the unavailable state is forced.
//

import XCTest

@MainActor
final class FridayModelNoteUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testChatShowsTheNoteWhenAppleIntelligenceIsOff() throws {
        let app = launchOffRecord(arguments: [
            "-UITesting",
            "-SemanticMemoryUITest",
            "-SemanticMemoryUseFallbackEmbeddings",
            "-FridayModelUnavailable", "appleIntelligenceOff",
        ])
        openFridayChat(in: app)

        let note = app.descendants(matching: .any)["friday.modelNote"].firstMatch
        scrollUntilVisible(note, in: app)
        XCTAssertTrue(note.waitForExistence(timeout: 6))
        XCTAssertTrue(note.label.localizedCaseInsensitiveContains("Apple Intelligence is off"))
    }

    func testChatHasNoNoteWhenTheModelIsSimplyOffForTests() throws {
        let app = launchOffRecord(arguments: [
            "-UITesting",
            "-SemanticMemoryUITest",
            "-SemanticMemoryUseFallbackEmbeddings",
        ])
        openFridayChat(in: app)

        XCTAssertTrue(app.descendants(matching: .any)["friday.askField"].firstMatch.waitForExistence(timeout: 8))
        XCTAssertFalse(app.descendants(matching: .any)["friday.modelNote"].firstMatch.exists)
    }

    private func openFridayChat(in app: XCUIApplication) {
        tapOffRecordTab("friday", in: app)
        let talkButton = app.buttons["friday.talk"].firstMatch
        let talk = talkButton.exists ? talkButton : app.descendants(matching: .any)["friday.talk"].firstMatch
        XCTAssertTrue(talk.waitForExistence(timeout: 8))
        talk.tap()
        XCTAssertTrue(app.descendants(matching: .any)["friday.askField"].firstMatch.waitForExistence(timeout: 8))
    }
}
