import XCTest

/// Person pages in My World, tags on entries and in Timeline, and multiple journals.
/// Fixtures: `UITestDataSeeder+Organize.swift`.
@MainActor
final class OrganizeUITests: XCTestCase {
    private let baseArguments = ["-UITesting", "-OrganizeUITest"]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: Person pages

    func testPersonPageShowsReadableEntriesAndHonorsRenameAndForget() throws {
        let app = launchOffRecord(arguments: baseArguments)
        openMyWorld(in: app)

        let row = app.buttons["friday.memoryRow.maya"].firstMatch
        scrollUntilVisible(row, in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        row.tap()

        let title = app.staticTexts["friday.knowledgePage.title"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 8))
        XCTAssertEqual(title.label, "Maya")
        let lead = app.staticTexts["friday.knowledgePage.lead"].firstMatch
        XCTAssertTrue(lead.label.contains("4 entries"), "Lead was \(lead.label)")
        XCTAssertTrue(app.descendants(matching: .any)["friday.knowledgePage.first"].firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)["friday.knowledgePage.chart"].firstMatch.exists)

        let entries = app.buttons.matching(identifier: "friday.knowledgePage.entry")
        scrollUntilVisible(entries.firstMatch, in: app)
        XCTAssertEqual(entries.count, 4)
        // The kept-out entry mentions Maya too, but the page never cites it.
        XCTAssertFalse(app.descendants(matching: .any).containingLabel("loan").firstMatch.exists)

        entries.firstMatch.tap()
        let back = app.buttons["entryDetail.backButton"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 8))
        back.tap()
        XCTAssertTrue(title.waitForExistence(timeout: 8))

        let rename = app.buttons["friday.memory.rename"].firstMatch
        scrollUntilVisible(rename, in: app)
        rename.tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        let field = alert.textFields.firstMatch
        field.tap()
        field.clearAndType("Mia")
        alert.buttons["Save"].firstMatch.tap()
        XCTAssertTrue(waitForElement(title, matching: NSPredicate(format: "label == %@", "Mia")))
        XCTAssertTrue(app.descendants(matching: .any).containingLabel("written as “Maya”").firstMatch.exists)

        let forget = app.buttons["friday.memory.forget"].firstMatch
        scrollUntilVisible(forget, in: app)
        forget.tap()
        let confirm = app.buttons.matching(NSPredicate(format: "label == %@", "Forget")).element(boundBy: 1)
        let forgetButton = confirm.waitForExistence(timeout: 3) ? confirm : app.sheets.buttons["Forget"].firstMatch
        XCTAssertTrue(forgetButton.waitForExistence(timeout: 5))
        forgetButton.tap()

        XCTAssertTrue(waitForElementToDisappear(title, timeout: 8))
        XCTAssertFalse(app.buttons["friday.memoryRow.maya"].firstMatch.exists)
        XCTAssertTrue(app.buttons["friday.memory.restore"].firstMatch.waitForExistence(timeout: 5))
    }

    // MARK: Tags

    func testTaggingAnEntryThenSearchingAndFilteringByTag() throws {
        let app = launchOffRecord(arguments: baseArguments)
        tapOffRecordTab("timeline", in: app)

        let dinner = snippet("Dinner with Maya", in: app)
        XCTAssertTrue(dinner.waitForExistence(timeout: 8))
        dinner.tap()

        let addTag = app.buttons["entryDetail.addTag"].firstMatch
        XCTAssertTrue(addTag.waitForExistence(timeout: 8))
        addTag.tap()
        let field = app.textFields["tagEditor.field"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("#Family\n")
        XCTAssertTrue(app.descendants(matching: .any)["tagEditor.remove.Family"].firstMatch.waitForExistence(timeout: 5))
        // Typing an existing tag in another case reuses it instead of making a second one.
        field.tap()
        field.typeText("work\n")
        XCTAssertTrue(app.descendants(matching: .any)["tagEditor.remove.Work"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["tagEditor.remove.Work"].firstMatch.tap()
        XCTAssertTrue(waitForElementToDisappear(app.descendants(matching: .any)["tagEditor.remove.Work"].firstMatch))
        app.buttons["tagEditor.done"].firstMatch.tap()

        XCTAssertTrue(app.buttons["entryDetail.tag.Family"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["entryDetail.backButton"].firstMatch.tap()

        // Filter by the Work tag.
        let filters = app.buttons["Filters"].firstMatch
        XCTAssertTrue(filters.waitForExistence(timeout: 8))
        filters.tap()
        let workFilter = app.buttons["timeline.tagFilter.Work"].firstMatch
        XCTAssertTrue(workFilter.waitForExistence(timeout: 5))
        workFilter.tap()
        XCTAssertTrue(app.descendants(matching: .any)["timeline.activeTagFilter"].firstMatch.waitForExistence(timeout: 5))
        // Close the filter bar so the matching entry sits on screen; the active chip stays.
        filters.tap()
        XCTAssertTrue(waitForElementToDisappear(workFilter))
        XCTAssertTrue(snippet("quarterly launch", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(waitForElementToDisappear(snippet("Dinner with Maya", in: app)))
        XCTAssertEqual(entryRows(in: app).count, 1)

        let clearAll = app.buttons["Clear All"].firstMatch
        XCTAssertTrue(clearAll.waitForExistence(timeout: 5))
        clearAll.tap()
        XCTAssertTrue(snippet("Dinner with Maya", in: app).waitForExistence(timeout: 5))

        // Search by tag: "#fam" finds the entry tagged Family and nothing else.
        let search = app.searchFields["timeline.searchField"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        search.tap()
        search.typeText("#fam")
        XCTAssertTrue(waitForElementToDisappear(snippet("quarterly launch", in: app)))
        XCTAssertTrue(snippet("Dinner with Maya", in: app).waitForExistence(timeout: 5))
        XCTAssertEqual(entryRows(in: app).count, 1)
    }

    func testRenamingATagOntoAnotherMergesThem() throws {
        let app = launchOffRecord(arguments: baseArguments)
        tapOffRecordTab("timeline", in: app)
        let dinner = snippet("Dinner with Maya", in: app)
        XCTAssertTrue(dinner.waitForExistence(timeout: 8))
        dinner.tap()
        XCTAssertTrue(app.buttons["entryDetail.addTag"].firstMatch.waitForExistence(timeout: 8))
        app.buttons["entryDetail.addTag"].firstMatch.tap()
        let field = app.textFields["tagEditor.field"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Job\n")
        app.buttons["tagEditor.done"].firstMatch.tap()
        app.buttons["entryDetail.backButton"].firstMatch.tap()

        tapOffRecordTab("settings", in: app)
        let manage = app.buttons["settings.tags.manage"].firstMatch
        scrollUntilVisible(manage, in: app)
        XCTAssertTrue(manage.waitForExistence(timeout: 8))
        manage.tap()

        let job = app.buttons["settings.tags.row.Job"].firstMatch
        XCTAssertTrue(job.waitForExistence(timeout: 5))
        job.tap()
        let renameAlert = app.alerts["Rename Tag"]
        XCTAssertTrue(renameAlert.waitForExistence(timeout: 5))
        renameAlert.textFields.firstMatch.clearAndType("work")
        renameAlert.buttons["Save"].firstMatch.tap()

        let mergeAlert = app.alerts.firstMatch
        XCTAssertTrue(mergeAlert.waitForExistence(timeout: 5))
        XCTAssertTrue(mergeAlert.label.contains("Merge Into Work"))
        mergeAlert.buttons["Merge"].firstMatch.tap()

        XCTAssertTrue(waitForElementToDisappear(job))
        let work = app.buttons["settings.tags.row.Work"].firstMatch
        XCTAssertTrue(work.waitForExistence(timeout: 5))
        XCTAssertTrue(work.label.contains("2 entries"), "Row was \(work.label)")
    }

    // MARK: Journals

    func testTimelineJournalPickerNarrowsEntries() throws {
        let app = launchOffRecord(arguments: baseArguments + ["-OrganizeWithJournal"])
        tapOffRecordTab("timeline", in: app)
        XCTAssertTrue(snippet("Packed for Goa", in: app).waitForExistence(timeout: 8))
        XCTAssertTrue(snippet("Dinner with Maya", in: app).exists)

        chooseTimelineJournal("Travel", in: app)
        XCTAssertTrue(waitForElementToDisappear(snippet("Dinner with Maya", in: app)))
        XCTAssertTrue(snippet("Packed for Goa", in: app).exists)
        XCTAssertEqual(entryRows(in: app).count, 1)

        chooseTimelineJournal("Main", in: app)
        XCTAssertTrue(waitForElementToDisappear(snippet("Packed for Goa", in: app)))
        XCTAssertTrue(snippet("Dinner with Maya", in: app).waitForExistence(timeout: 5))

        chooseTimelineJournal("All Journals", in: app)
        XCTAssertTrue(snippet("Packed for Goa", in: app).waitForExistence(timeout: 5))
    }

    func testCreatingAndDeletingJournalsInSettings() throws {
        let app = launchOffRecord(arguments: baseArguments + ["-OrganizeWithJournal"])
        tapOffRecordTab("settings", in: app)
        let manage = app.buttons["settings.journals.manage"].firstMatch
        scrollUntilVisible(manage, in: app)
        XCTAssertTrue(manage.waitForExistence(timeout: 8))
        manage.tap()

        app.buttons["settings.journals.add"].firstMatch.tap()
        let newAlert = app.alerts["New Journal"]
        XCTAssertTrue(newAlert.waitForExistence(timeout: 5))
        newAlert.textFields.firstMatch.tap()
        newAlert.textFields.firstMatch.typeText("Work")
        newAlert.buttons["Create"].firstMatch.tap()
        XCTAssertTrue(app.buttons["settings.journals.row.Work"].firstMatch.waitForExistence(timeout: 5))

        // The main journal's name is taken.
        app.buttons["settings.journals.add"].firstMatch.tap()
        XCTAssertTrue(newAlert.waitForExistence(timeout: 5))
        newAlert.textFields.firstMatch.tap()
        newAlert.textFields.firstMatch.typeText("main")
        newAlert.buttons["Create"].firstMatch.tap()
        let error = app.alerts["Couldn’t Save Journal"]
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        error.buttons["OK"].firstMatch.tap()

        let travel = app.buttons["settings.journals.row.Travel"].firstMatch
        XCTAssertTrue(travel.waitForExistence(timeout: 5))
        travel.swipeLeft()
        app.buttons["Delete"].firstMatch.tap()
        let move = app.buttons["settings.journals.delete.move"].firstMatch
        XCTAssertTrue(move.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings.journals.delete.entries"].firstMatch.exists)
        move.tap()
        XCTAssertTrue(waitForElementToDisappear(travel))

        // Its entry now sits in the main journal.
        tapOffRecordTab("timeline", in: app)
        chooseTimelineJournal("Main", in: app)
        XCTAssertTrue(snippet("Packed for Goa", in: app).waitForExistence(timeout: 8))
    }

    func testCaptureSheetPicksTheJournal() throws {
        let app = launchOffRecord(arguments: baseArguments + ["-OrganizeWithJournal", "-HeroNudgeUITest"])
        let record = app.descendants(matching: .any)["todayDock.record"].firstMatch
        XCTAssertTrue(record.waitForExistence(timeout: 8))
        record.tap()

        let picker = app.buttons["capture.journalPicker"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 8))
        XCTAssertTrue(picker.label.contains("Main"), "Picker was \(picker.label)")
        picker.tap()
        let travel = app.buttons["Travel"].firstMatch
        XCTAssertTrue(travel.waitForExistence(timeout: 5))
        travel.tap()
        XCTAssertTrue(waitForElement(picker, matching: NSPredicate(format: "label CONTAINS %@", "Travel")))
    }

    // MARK: Helpers

    /// Timeline entry buttons (`timeline.entryRow.<id>`).
    private func entryRows(in app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "timeline.entryRow."))
    }

    /// The preview text of the Timeline entry that contains `text`.
    private func snippet(_ text: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@ OR identifier == %@", "timeline.entrySnippet", "timeline.evidenceSnippet"))
            .containingLabel(text)
            .firstMatch
    }

    private func openMyWorld(in app: XCUIApplication) {
        tapOffRecordTab("friday", in: app)
        let section = app.buttons["My World section"].firstMatch
        XCTAssertTrue(section.waitForExistence(timeout: 8))
        if !section.isHittable {
            app.buttons["Emotions section"].firstMatch.swipeLeft()
        }
        section.tap()
    }

    private func chooseTimelineJournal(_ name: String, in app: XCUIApplication) {
        let picker = app.buttons["timeline.journalPicker"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 8))
        picker.tap()
        let option = app.buttons[name].firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5), "Missing journal option \(name)")
        option.tap()
    }
}

private extension XCUIElement {
    func clearAndType(_ text: String) {
        tap()
        if let value = value as? String, !value.isEmpty {
            typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
        }
        typeText(text)
    }
}
