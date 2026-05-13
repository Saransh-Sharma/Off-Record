//
//  SemanticMemoryUITests.swift
//  OffRecordUITests
//
//  Deterministic UI coverage for Semantic Memory and evidence-backed Friday.
//

import XCTest

@MainActor
final class SemanticMemoryUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSettingsShowsSemanticMemoryStatusAndFallback() throws {
        let app = launchSemanticMemoryApp()
        waitForSemanticIndexReady(app)
        openSemanticMemorySettings(app)

        XCTAssertTrue(app.descendants(matching: .any)["semanticMemory.section"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["semanticMemory.statusMessage"].waitForExistence(timeout: 4))
        let fallbackWarning = app.descendants(matching: .any)["semanticMemory.fallbackWarning"].firstMatch
        scrollUntilExists(fallbackWarning, in: app)
        XCTAssertTrue(fallbackWarning.waitForExistence(timeout: 4))
        XCTAssertTrue(indexedChunkCount(in: app) > 0)
        let rebuild = app.buttons["semanticMemory.rebuild"]
        scrollUntilExists(rebuild, in: app)
        XCTAssertTrue(rebuild.waitForExistence(timeout: 4))
        let delete = app.buttons["semanticMemory.delete"]
        scrollUntilExists(delete, in: app)
        XCTAssertTrue(delete.waitForExistence(timeout: 4))
    }

    func testDeletingSemanticIndexPreservesJournalEntries() throws {
        let app = launchSemanticMemoryApp()
        waitForSemanticIndexReady(app)
        openSemanticMemorySettings(app)

        deleteSemanticIndex(app)

        XCTAssertTrue(waitForChunkCount(app, equals: 0, timeout: 8))
        XCTAssertTrue(app.staticTexts["semanticMemory.statusMessage"].label.localizedCaseInsensitiveContains("deleted"))

        app.buttons["tab.timeline"].tap()
        XCTAssertTrue(app.staticTexts.matching(labelContaining: "quarterly review").firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts.matching(labelContaining: "Bangalore cafe").firstMatch.waitForExistence(timeout: 4))
    }

    func testDeletingSemanticIndexShowsUnavailableSettingsCopy() throws {
        let app = launchSemanticMemoryApp()
        waitForSemanticIndexReady(app)
        openSemanticMemorySettings(app)

        deleteSemanticIndex(app)

        let status = app.staticTexts["semanticMemory.statusMessage"]
        XCTAssertTrue(status.waitForExistence(timeout: 4))
        XCTAssertTrue(status.label.localizedCaseInsensitiveContains("deleted"))
        XCTAssertTrue(status.label.localizedCaseInsensitiveContains("rebuild"))
    }

    func testRebuildAfterDeleteRestoresSearch() throws {
        let app = launchSemanticMemoryApp()
        waitForSemanticIndexReady(app)
        openSemanticMemorySettings(app)

        deleteSemanticIndex(app)
        rebuildSemanticIndex(app)

        XCTAssertTrue(waitForChunkCountGreaterThanZero(app, timeout: 15))
        XCTAssertTrue(waitForSemanticIndexReady(app))
        assertWorkStressSearch(in: app)
    }

    func testTimelineSearchSurfacesWorkStressEvidence() throws {
        let app = launchSemanticMemoryApp()
        waitForSemanticIndexReady(app)

        assertWorkStressSearch(in: app)
        XCTAssertTrue(app.descendants(matching: .any)["timeline.evidenceSnippet"].firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifierPrefix: "timeline.evidenceReason.").firstMatch.exists)
    }

    func testTimelineSearchPreservesExactPersonPlaceRanking() throws {
        let app = launchSemanticMemoryApp()
        waitForSemanticIndexReady(app)

        app.buttons["tab.timeline"].tap()
        enterSearch("Maya Bangalore", in: app)

        let mayaDinner = app.staticTexts.matching(labelContaining: "Dinner with Maya and Arjun").firstMatch
        let bangaloreCafe = app.staticTexts.matching(labelContaining: "Bangalore cafe").firstMatch
        let unrelated = app.staticTexts.matching(labelContaining: "organizing old books").firstMatch

        XCTAssertTrue(mayaDinner.waitForExistence(timeout: 12))
        XCTAssertTrue(bangaloreCafe.waitForExistence(timeout: 4))
        XCTAssertTrue(
            app.descendants(matching: .any)["timeline.evidenceReason.Exact match"].firstMatch.waitForExistence(timeout: 4)
            || app.descendants(matching: .any)["timeline.evidenceReason.Person or topic match"].firstMatch.waitForExistence(timeout: 4)
        )
        if unrelated.exists {
            XCTAssertLessThan(mayaDinner.frame.minY, unrelated.frame.minY)
        }
    }

    func testTimelineShowsBuildingStateWhileIndexing() throws {
        let app = launchSemanticMemoryApp(extraArguments: ["-SemanticMemorySlowIndexingUITest"])

        app.buttons["tab.timeline"].tap()
        enterSearch("stress after work", in: app)

        let buildingTitle = app.descendants(matching: .any)["semanticMemory.buildingTitle"].firstMatch
        let searchMessage = app.descendants(matching: .any)["semanticMemory.searchMessage"].firstMatch
        XCTAssertTrue(
            buildingTitle.waitForExistence(timeout: 4) || searchMessage.waitForExistence(timeout: 4),
            "Timeline should expose the typed building/searching state while the local index is unavailable."
        )

        XCTAssertTrue(waitForSearchResult(containing: "work stress and pressure", in: app, timeout: 20))
    }

    func testFridayFreeformSupportedQuestionShowsCitedEvidence() throws {
        let app = launchSemanticMemoryApp()
        waitForSemanticIndexReady(app)

        askFriday("What did I write about work stress and pressure?", in: app)

        XCTAssertTrue(app.staticTexts["friday.answerMessage"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any)["friday.evidenceRail"].firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["friday.evidenceChip"].firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)["friday.evidenceChip.snippet"].firstMatch.label.localizedCaseInsensitiveContains("work"))
        XCTAssertTrue(app.descendants(matching: .any)["friday.evidenceChip.mood"].firstMatch.waitForExistence(timeout: 4))
        XCTAssertTrue(app.descendants(matching: .any)["friday.evidenceChip.reason"].firstMatch.waitForExistence(timeout: 4))
    }

    func testFridaySuggestedQuestionAttachesEvidence() throws {
        let app = launchSemanticMemoryApp()
        waitForSemanticIndexReady(app)

        openFridayChat(app)
        let chip = app.descendants(matching: .any)["friday.questionChip.stressTriggers"].firstMatch
        scrollQuestionChipIntoView(chip, in: app)
        XCTAssertTrue(chip.waitForExistence(timeout: 8))
        XCTAssertTrue(elementFrameIsVisible(chip, in: app))
        chip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        XCTAssertTrue(app.staticTexts["friday.answerMessage"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any)["friday.evidenceRail"].firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["friday.evidenceChip.snippet"].firstMatch.waitForExistence(timeout: 4))
    }

    func testFridayUnsupportedQuestionRefusesWithoutEvidence() throws {
        let app = launchSemanticMemoryApp()
        waitForSemanticIndexReady(app)

        askFriday("What did I write about scuba diving in Lisbon?", in: app)

        let answer = app.staticTexts["friday.answerMessage"]
        XCTAssertTrue(answer.waitForExistence(timeout: 15))
        XCTAssertTrue(answer.label.localizedCaseInsensitiveContains("not have enough journal evidence"))
        XCTAssertTrue(app.staticTexts["friday.limitations"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.descendants(matching: .any)["friday.evidenceRail"].firstMatch.exists)
    }

    func testFridayEvidenceChipDeepLinksToEntry() throws {
        let app = launchSemanticMemoryApp()
        waitForSemanticIndexReady(app)

        askFriday("What did I write about work stress and pressure?", in: app)
        openFirstEvidenceChip(app)

        let entryText = app.staticTexts["entryDetail.mainText"].firstMatch
        XCTAssertTrue(entryText.waitForExistence(timeout: 8))
        XCTAssertTrue(entryText.label.localizedCaseInsensitiveContains("work stress and pressure"))
        XCTAssertTrue(entryText.label.localizedCaseInsensitiveContains("Maya reminded me"))
    }

    private func launchSemanticMemoryApp(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-UITesting",
            "-SemanticMemoryUITest",
            "-SemanticMemoryUseFallbackEmbeddings"
        ] + extraArguments
        app.launch()
        XCTAssertTrue(app.buttons["tab.today"].waitForExistence(timeout: 10))
        return app
    }

    @discardableResult
    private func waitForSemanticIndexReady(_ app: XCUIApplication, timeout: TimeInterval = 15) -> Bool {
        app.buttons["tab.timeline"].tap()
        enterSearch("stress after work", in: app)
        guard waitForSearchResult(containing: "work stress and pressure", in: app, timeout: timeout) else {
            return false
        }

        app.buttons["tab.settings"].tap()
        let section = app.descendants(matching: .any)["semanticMemory.section"].firstMatch
        scrollUntilExists(section, in: app)
        return waitForChunkCountGreaterThanZero(app, timeout: timeout)
    }

    private func openSemanticMemorySettings(_ app: XCUIApplication) {
        app.buttons["tab.settings"].tap()
        let section = app.descendants(matching: .any)["semanticMemory.section"].firstMatch
        scrollUntilExists(section, in: app)
        XCTAssertTrue(section.waitForExistence(timeout: 8))
    }

    private func deleteSemanticIndex(_ app: XCUIApplication) {
        let deleteButton = app.buttons["semanticMemory.delete"]
        scrollUntilExists(deleteButton, in: app)
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 4))
        deleteButton.tap()

        let confirm = app.buttons["Delete Local Index"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 4))
        confirm.tap()
    }

    private func rebuildSemanticIndex(_ app: XCUIApplication) {
        let rebuildButton = app.buttons["semanticMemory.rebuild"]
        scrollUntilExists(rebuildButton, in: app)
        XCTAssertTrue(rebuildButton.waitForExistence(timeout: 4))
        rebuildButton.tap()
    }

    private func assertWorkStressSearch(in app: XCUIApplication) {
        app.buttons["tab.timeline"].tap()
        enterSearch("stress after work", in: app)

        XCTAssertTrue(waitForSearchResult(containing: "work stress and pressure", in: app, timeout: 15))
        XCTAssertTrue(app.staticTexts.matching(labelContaining: "Maya reminded me").firstMatch.exists)
    }

    private func enterSearch(_ text: String, in app: XCUIApplication) {
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 8))
        searchField.tap()
        if let value = searchField.value as? String,
           !value.isEmpty,
           value != "Search entries" {
            searchField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
        }
        searchField.typeText(text)
    }

    private func waitForSearchResult(containing text: String, in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        app.staticTexts.matching(labelContaining: text).firstMatch.waitForExistence(timeout: timeout)
    }

    private func askFriday(_ question: String, in app: XCUIApplication) {
        openFridayChat(app)
        let field = app.textFields["friday.askField"]
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        field.tap()
        field.typeText(question)

        let askButton = app.buttons["friday.askButton"]
        XCTAssertTrue(askButton.waitForExistence(timeout: 4))
        askButton.tap()
        XCTAssertTrue(app.staticTexts["friday.userMessage"].waitForExistence(timeout: 4))
    }

    private func openFridayChat(_ app: XCUIApplication) {
        app.buttons["tab.friday"].tap()
        let talkToFriday = app.descendants(matching: .any)["friday.talk"].firstMatch
        XCTAssertTrue(talkToFriday.waitForExistence(timeout: 8))
        talkToFriday.tap()
    }

    private func scrollQuestionChipIntoView(_ chip: XCUIElement, in app: XCUIApplication) {
        let scroller = app.scrollViews["friday.questionChips"].firstMatch
        XCTAssertTrue(scroller.waitForExistence(timeout: 8))
        for _ in 0..<6 where !elementFrameIsVisible(chip, in: app) {
            scroller.swipeLeft()
        }
    }

    private func elementFrameIsVisible(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        guard element.exists else { return false }
        let midpoint = CGPoint(x: element.frame.midX, y: element.frame.midY)
        return app.frame.insetBy(dx: 8, dy: 8).contains(midpoint)
    }

    private func openFirstEvidenceChip(_ app: XCUIApplication) {
        let chip = app.descendants(matching: .any)["friday.evidenceChip"].firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 12))
        chip.tap()
    }

    private func waitForChunkCountGreaterThanZero(_ app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "label MATCHES %@", "[1-9][0-9]*")
        let element = app.staticTexts["semanticMemory.chunkCount"].firstMatch
        return wait(for: element, matching: predicate, timeout: timeout)
    }

    private func waitForChunkCount(_ app: XCUIApplication, equals count: Int, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "label == %@", "\(count)")
        let element = app.staticTexts["semanticMemory.chunkCount"].firstMatch
        return wait(for: element, matching: predicate, timeout: timeout)
    }

    private func indexedChunkCount(in app: XCUIApplication) -> Int {
        Int(app.staticTexts["semanticMemory.chunkCount"].firstMatch.label) ?? 0
    }

    private func wait(for element: XCUIElement, matching predicate: NSPredicate, timeout: TimeInterval) -> Bool {
        guard element.waitForExistence(timeout: timeout) else { return false }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    private func scrollUntilExists(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 8) {
        guard !element.exists else { return }
        for _ in 0..<maxSwipes where !element.exists {
            app.swipeUp()
        }
    }
}

private extension XCUIElementQuery {
    func matching(labelContaining text: String) -> XCUIElementQuery {
        matching(NSPredicate(format: "label CONTAINS[c] %@", text))
    }

    func matching(identifierPrefix prefix: String) -> XCUIElementQuery {
        matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
    }
}
