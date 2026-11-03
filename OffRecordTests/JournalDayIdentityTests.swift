import CoreData
import Foundation
import JournalFoundation
import Testing
@testable import OffRecord

/// Multiple journals: a day's identity is (day, journal), merges stay inside one
/// journal, deleting a journal moves or deletes its entries, and Record and Write
/// default to the last journal picked or the main journal.
@MainActor
@Suite(.serialized)
struct JournalDayIdentityTests {

    // MARK: Day identity

    @Test func eachJournalGetsItsOwnEntryForTheDay() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let work = try JournalStore(context: context).createJournal(named: "Work")
        let day = makeDate(day: 12, hour: 9)

        let main = try DiaryEntryDailyStore.getOrCreateEntry(on: day, in: context)
        let workEntry = try DiaryEntryDailyStore.getOrCreateEntry(on: makeDate(day: 12, hour: 18), journal: work, in: context)
        try context.save()

        #expect(main.objectID != workEntry.objectID)
        #expect(main.journal == nil)
        #expect(workEntry.journal == work)
        #expect(try DiaryEntryDailyStore.getOrCreateEntry(on: makeDate(day: 12, hour: 20), in: context).objectID == main.objectID)
        #expect(try DiaryEntryDailyStore.getOrCreateEntry(on: makeDate(day: 12, hour: 21), journal: work, in: context).objectID == workEntry.objectID)
        #expect(try DiaryEntryDailyStore.entries(on: day, in: context).map(\.objectID) == [main.objectID])
        #expect(try DiaryEntryDailyStore.entries(on: day, journal: work, in: context).map(\.objectID) == [workEntry.objectID])
    }

    @Test func appendingTextStaysInTheChosenJournal() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let work = try JournalStore(context: context).createJournal(named: "Work")

        let mainEntry = try JournalBlockTimelineStore.appendTextBlock(text: "Walked by the lake.", createdAt: makeDate(day: 3, hour: 8), in: context)
        let workEntry = try JournalBlockTimelineStore.appendTextBlock(text: "Planned the launch.", createdAt: makeDate(day: 3, hour: 10), journal: work, in: context)
        try context.save()

        #expect(mainEntry.journal == nil)
        #expect(workEntry.journal == work)
        #expect(mainEntry.text?.contains("Planned the launch.") == false)
        #expect(workEntry.text?.contains("Walked by the lake.") == false)
    }

    @Test func mergingNeverCrossesJournals() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let work = try JournalStore(context: context).createJournal(named: "Work")
        makeEntry("Morning in main", on: makeDate(day: 20, hour: 8), updatedAt: makeDate(day: 20, hour: 8), in: context)
        makeEntry("Evening in main", on: makeDate(day: 20, hour: 19), updatedAt: makeDate(day: 20, hour: 19), in: context)
        let workEntry = makeEntry("Standup notes", on: makeDate(day: 20, hour: 10), updatedAt: makeDate(day: 20, hour: 21), journal: work, in: context)
        try context.save()

        let merged = try DiaryEntryDailyStore.normalizeAllDuplicateDays(in: context)
        try context.save()

        #expect(merged.count == 1)
        let mainEntries = try DiaryEntryDailyStore.entries(on: makeDate(day: 20, hour: 12), in: context)
        let workEntries = try DiaryEntryDailyStore.entries(on: makeDate(day: 20, hour: 12), journal: work, in: context)
        #expect(mainEntries.count == 1)
        #expect(mainEntries.first?.text?.contains("Morning in main") == true)
        #expect(mainEntries.first?.text?.contains("Evening in main") == true)
        #expect(mainEntries.first?.text?.contains("Standup notes") == false)
        #expect(workEntries.map(\.objectID) == [workEntry.objectID])
        #expect(workEntry.text == "Standup notes")
    }

    @Test func normalizingOneJournalLeavesTheOthersAlone() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let work = try JournalStore(context: context).createJournal(named: "Work")
        makeEntry("Main one", on: makeDate(day: 21, hour: 8), in: context)
        makeEntry("Main two", on: makeDate(day: 21, hour: 9), in: context)
        makeEntry("Work one", on: makeDate(day: 21, hour: 10), journal: work, in: context)
        makeEntry("Work two", on: makeDate(day: 21, hour: 11), journal: work, in: context)
        try context.save()

        try DiaryEntryDailyStore.normalizeDuplicateEntries(on: makeDate(day: 21, hour: 12), journal: work, in: context)
        try context.save()

        #expect(try DiaryEntryDailyStore.entries(on: makeDate(day: 21, hour: 12), journal: work, in: context).count == 1)
        #expect(try DiaryEntryDailyStore.entries(on: makeDate(day: 21, hour: 12), in: context).count == 2)
    }

    @Test func mergeKeepsEveryTagAndTheStrictestExclusion() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let tags = TagStore(context: context)
        let family = try tags.createTag(named: "Family")
        let travel = try tags.createTag(named: "Travel")
        let first = makeEntry("Packed for Goa", on: makeDate(day: 22, hour: 8), updatedAt: makeDate(day: 22, hour: 20), in: context)
        let second = makeEntry("Called Maya", on: makeDate(day: 22, hour: 9), updatedAt: makeDate(day: 22, hour: 9), in: context)
        first.addToTags(travel)
        second.addToTags(family)
        second.journalAIExclusion = .excludedFromAI
        try context.save()

        let merged = try #require(try DiaryEntryDailyStore.normalizeDuplicateEntries(on: makeDate(day: 22, hour: 12), in: context))
        try context.save()

        #expect(Set(tags.tags(for: merged).compactMap(\.name)) == ["Family", "Travel"])
        #expect(merged.journalAIExclusion == .excludedFromAI)
    }

    // MARK: Moving

    @Test func movingAnEntryMergesItIntoThatJournalsDay() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let store = JournalStore(context: context)
        let work = try store.createJournal(named: "Work")
        let existing = makeEntry("Review prep", on: makeDate(day: 5, hour: 9), updatedAt: makeDate(day: 5, hour: 9), journal: work, in: context)
        let moving = makeEntry("Thoughts after the review", on: makeDate(day: 5, hour: 17), updatedAt: makeDate(day: 5, hour: 17), in: context)
        let existingID = try #require(existing.id)
        try context.save()

        let result = try store.move(moving, to: work)

        #expect(!moving.isDeleted)
        #expect(moving.journal == work)
        #expect(result.deletedEntryIDs == [existingID])
        #expect(result.updatedEntries.map(\.objectID) == [moving.objectID])
        let workEntries = try DiaryEntryDailyStore.entries(on: makeDate(day: 5, hour: 12), journal: work, in: context)
        #expect(workEntries.count == 1)
        #expect(workEntries.first?.text?.contains("Review prep") == true)
        #expect(workEntries.first?.text?.contains("Thoughts after the review") == true)
        #expect(try DiaryEntryDailyStore.entries(on: makeDate(day: 5, hour: 12), in: context).isEmpty)
    }

    // MARK: Deleting a journal

    @Test func deletingAJournalCanMoveItsEntriesToMain() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let store = JournalStore(context: context)
        let work = try store.createJournal(named: "Work")
        makeEntry("Main day one", on: makeDate(day: 7, hour: 8), updatedAt: makeDate(day: 7, hour: 8), in: context)
        makeEntry("Work day one", on: makeDate(day: 7, hour: 10), updatedAt: makeDate(day: 7, hour: 10), journal: work, in: context)
        makeEntry("Work day two", on: makeDate(day: 8, hour: 10), journal: work, in: context)
        try context.save()

        let result = try store.delete(work, choice: .moveEntriesToMain)

        #expect(store.journals(includingArchived: true).isEmpty)
        let dayOne = try DiaryEntryDailyStore.entries(on: makeDate(day: 7, hour: 12), in: context)
        let dayTwo = try DiaryEntryDailyStore.entries(on: makeDate(day: 8, hour: 12), in: context)
        #expect(dayOne.count == 1)
        #expect(dayOne.first?.text?.contains("Main day one") == true)
        #expect(dayOne.first?.text?.contains("Work day one") == true)
        #expect(dayTwo.count == 1)
        #expect(dayTwo.first?.text == "Work day two")
        #expect(result.deletedEntryIDs.count == 1)
        #expect(result.updatedEntries.count == 2)
        let allEntries: NSFetchRequest<DiaryEntry> = DiaryEntry.fetchRequest()
        #expect(try context.count(for: allEntries) == 2)
    }

    @Test func deletingAJournalCanDeleteItsEntries() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let store = JournalStore(context: context)
        let work = try store.createJournal(named: "Work")
        let main = makeEntry("Stays in main", on: makeDate(day: 9, hour: 8), in: context)
        let gone = makeEntry("Goes with the journal", on: makeDate(day: 9, hour: 10), journal: work, in: context)
        let goneID = try #require(gone.id)
        try context.save()

        let result = try store.delete(work, choice: .deleteEntries)

        #expect(result.deletedEntryIDs == [goneID])
        #expect(store.journals(includingArchived: true).isEmpty)
        let request: NSFetchRequest<DiaryEntry> = DiaryEntry.fetchRequest()
        let remaining = try context.fetch(request)
        #expect(remaining.map(\.objectID) == [main.objectID])
        #expect(main.text == "Stays in main")
    }

    @Test func deletingTheLastPickedJournalFallsBackToMain() throws {
        let saved = UserDefaults.standard.object(forKey: JournalSelectionPreference.defaultsKey)
        defer { UserDefaults.standard.set(saved, forKey: JournalSelectionPreference.defaultsKey) }
        let context = PersistenceController(inMemory: true).container.viewContext
        let store = JournalStore(context: context)
        let work = try store.createJournal(named: "Work")
        JournalSelectionPreference.remember(work)

        try store.delete(work, choice: .moveEntriesToMain)

        #expect(JournalSelectionPreference.lastUsedJournalID == nil)
        #expect(JournalSelectionPreference.defaultJournal(in: context) == nil)
    }

    // MARK: Capture default

    @Test func captureDefaultsToTheLastPickedJournalOrMain() throws {
        let saved = UserDefaults.standard.object(forKey: JournalSelectionPreference.defaultsKey)
        defer { UserDefaults.standard.set(saved, forKey: JournalSelectionPreference.defaultsKey) }
        let context = PersistenceController(inMemory: true).container.viewContext
        let store = JournalStore(context: context)
        let work = try store.createJournal(named: "Work")

        JournalSelectionPreference.remember(nil)
        #expect(JournalSelectionPreference.defaultJournal(in: context) == nil)

        JournalSelectionPreference.remember(work)
        #expect(JournalSelectionPreference.defaultJournal(in: context) == work)

        try store.setArchived(work, true)
        #expect(JournalSelectionPreference.defaultJournal(in: context) == nil)

        try store.setArchived(work, false)
        JournalSelectionPreference.lastUsedJournalID = UUID()
        #expect(JournalSelectionPreference.defaultJournal(in: context) == nil)
    }

    // MARK: Names and scopes

    @Test func journalNamesStayDistinctFromEachOtherAndMain() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let store = JournalStore(context: context)
        let work = try store.createJournal(named: "Work")

        #expect(store.isNameTaken(" work "))
        #expect(store.isNameTaken("main"))
        #expect(!store.isNameTaken("Work", excluding: work))
        #expect(!store.isNameTaken("Travel"))
    }

    @Test func scopesPickEntriesByJournal() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let work = try JournalStore(context: context).createJournal(named: "Work")
        let main = makeEntry("Main", on: makeDate(day: 1, hour: 9), in: context)
        let workEntry = makeEntry("Work", on: makeDate(day: 1, hour: 10), journal: work, in: context)
        let workID = try #require(work.id)

        #expect(JournalScope.all.filter([main, workEntry]).count == 2)
        #expect(JournalScope.main.filter([main, workEntry]).map(\.objectID) == [main.objectID])
        #expect(JournalScope.journal(workID).filter([main, workEntry]).map(\.objectID) == [workEntry.objectID])
        #expect(JournalScope(journal: work) == .journal(workID))
        #expect(JournalScope(journal: nil) == .main)
    }

    // MARK: Helpers

    @discardableResult
    private func makeEntry(
        _ text: String,
        on date: Date,
        updatedAt: Date? = nil,
        journal: Journal? = nil,
        in context: NSManagedObjectContext
    ) -> DiaryEntry {
        let entry = DiaryEntry(context: context)
        entry.id = UUID()
        entry.date = date
        entry.createdAt = date
        entry.updatedAt = updatedAt ?? date
        entry.text = text
        entry.isStarred = false
        entry.journal = journal
        return entry
    }

    private func makeDate(day: Int, hour: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar.current
        components.year = 2026
        components.month = 3
        components.day = day
        components.hour = hour
        return Calendar.current.date(from: components) ?? Date()
    }
}
