import CoreData
import Foundation
import Testing
@testable import OffRecord

/// Tags: names are trimmed and unique ignoring case, renaming onto an existing
/// name merges, deleting leaves entries alone, Timeline's tag search and filter
/// match the right entries, and imported tags reuse existing ones.
@MainActor
@Suite(.serialized)
struct TagOrganizationTests {

    // MARK: Normalization

    @Test func namesAreTrimmedWithoutHashesOrExtraSpaces() {
        #expect(TagStore.normalizedName("  Work  ") == "Work")
        #expect(TagStore.normalizedName("#work") == "work")
        #expect(TagStore.normalizedName("## deep   work ") == "deep work")
        #expect(TagStore.normalizedName("#") == "")
        #expect(TagStore.normalizedName("   ") == "")
        #expect(TagStore.normalizedName(String(repeating: "a", count: 60)).count == TagStore.maximumNameLength)
    }

    @Test func emptyNamesAreRefused() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let entry = makeEntry("Lunch with Maya.", in: context)
        #expect(throws: JournalOrganizationError.emptyName) { try TagStore(context: context).addTag(named: " # ", to: entry) }
        #expect(TagStore(context: context).allTags().isEmpty)
    }

    // MARK: Uniqueness

    @Test func addingATagReusesOneWithTheSameNameIgnoringCase() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let store = TagStore(context: context)
        let first = makeEntry("Standup ran long.", in: context)
        let second = makeEntry("Shipped the release.", in: context)

        let work = try store.addTag(named: "Work", to: first)
        let again = try store.addTag(named: "  #work ", to: second)
        try store.addTag(named: "WORK", to: second)

        #expect(again.objectID == work.objectID)
        #expect(store.allTags().count == 1)
        #expect(store.tags(for: second).map(\.name) == ["Work"])
        #expect(store.entryCount(for: work) == 2)
    }

    @Test func taggingAnEntryUpdatesItSoListsRefresh() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let entry = makeEntry("Walk by the lake.", in: context)
        let before = Date(timeIntervalSince1970: 1_700_000_000)
        entry.updatedAt = before
        try context.save()

        let tag = try TagStore(context: context).addTag(named: "Walks", to: entry)
        #expect((entry.updatedAt ?? before) > before)

        entry.updatedAt = before
        try TagStore(context: context).removeTag(tag, from: entry)
        #expect((entry.updatedAt ?? before) > before)
        #expect(TagStore(context: context).tags(for: entry).isEmpty)
    }

    // MARK: Rename and merge

    @Test func renamingToAFreeNameKeepsTheTag() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let store = TagStore(context: context)
        let entry = makeEntry("Packed for Goa.", in: context)
        let trips = try store.addTag(named: "Trips", to: entry)

        let renamed = try store.renameOrMerge(trips, to: " Travel ")
        #expect(renamed.objectID == trips.objectID)
        #expect(trips.name == "Travel")

        // A change of case is a rename of the same tag, not a merge.
        let recased = try store.renameOrMerge(trips, to: "travel")
        #expect(recased.objectID == trips.objectID)
        #expect(trips.name == "travel")
    }

    @Test func renamingOntoAnExistingNameMergesTheTags() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let store = TagStore(context: context)
        let both = makeEntry("Office party.", in: context)
        let onlyJob = makeEntry("Long review.", in: context)
        let work = try store.addTag(named: "Work", to: both)
        let job = try store.addTag(named: "Job", to: both)
        try store.addTag(named: "Job", to: onlyJob)

        let survivor = try store.renameOrMerge(job, to: "work")

        #expect(survivor.objectID == work.objectID)
        #expect(job.isDeleted || job.managedObjectContext == nil)
        #expect(store.allTags().map(\.name) == ["Work"])
        #expect(store.tags(for: both).map(\.name) == ["Work"])
        #expect(store.tags(for: onlyJob).map(\.name) == ["Work"])
        #expect(store.entryCount(for: work) == 2)
    }

    @Test func deletingATagLeavesItsEntries() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let store = TagStore(context: context)
        let entry = makeEntry("Dinner with family.", in: context)
        let family = try store.addTag(named: "Family", to: entry)
        try store.addTag(named: "Food", to: entry)

        try store.deleteTag(family)

        #expect(!entry.isDeleted)
        #expect(entry.text == "Dinner with family.")
        #expect(store.tags(for: entry).map(\.name) == ["Food"])
    }

    // MARK: Suggestions

    @Test func suggestionsPutPrefixMatchesFirstAndSkipTheEntrysTags() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let store = TagStore(context: context)
        let entry = makeEntry("Notes.", in: context)
        let other = makeEntry("More notes.", in: context)
        try store.addTag(named: "Homework", to: other)
        try store.addTag(named: "Work", to: other)
        try store.addTag(named: "Workout", to: entry)
        try store.addTag(named: "Family", to: other)

        let excluded = Set(store.tags(for: entry).map(\.objectID))
        #expect(store.suggestions(for: "wor", excluding: excluded).map(\.name) == ["Work", "Homework"])
        #expect(store.suggestions(for: "#WOR").map(\.name) == ["Work", "Workout", "Homework"])
        #expect(store.suggestions(for: "zz").isEmpty)
    }

    // MARK: Filtering and search

    @Test func timelineTagSearchAndFilterMatchTheRightEntries() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let store = TagStore(context: context)
        let tagged = makeEntry("Long day at the office.", in: context)
        let untagged = makeEntry("Work was quiet.", in: context)
        let work = try store.addTag(named: "Work", to: tagged)
        let workID = try #require(work.id)

        #expect(TagSearch.hashtagQuery("#wor") == "wor")
        #expect(TagSearch.hashtagQuery("work") == nil)
        #expect(TagSearch.hashtagQuery(" # ") == "")

        #expect(TagSearch.entry(tagged, matchesHashtag: "wor"))
        #expect(!TagSearch.entry(untagged, matchesHashtag: "wor"))
        #expect(TagSearch.entry(tagged, matchesHashtag: ""))
        #expect(!TagSearch.entry(untagged, matchesHashtag: ""))
        #expect(!TagSearch.entry(tagged, matchesHashtag: "ork"))

        #expect(TagSearch.entry(tagged, hasTagNamed: "work"))
        #expect(!TagSearch.entry(tagged, hasTagNamed: "wor"))
        #expect(!TagSearch.entry(untagged, hasTagNamed: "work"))

        #expect(TagSearch.entry(tagged, hasTagWithID: workID))
        #expect(!TagSearch.entry(untagged, hasTagWithID: workID))
    }

    // MARK: Imports

    @Test func importedTagsReuseExistingOnesAndDontSave() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let store = TagStore(context: context)
        let existingEntry = makeEntry("Earlier.", in: context)
        let work = try store.addTag(named: "Work", to: existingEntry)
        let imported = makeEntry("Imported from Day One.", in: context)

        let applied = ImportedTagMapper.apply(["#work", " Work ", "Travel", "", "#", "travel"], to: imported, in: context)

        #expect(context.hasChanges)
        #expect(applied.count == 2)
        #expect(applied.first?.objectID == work.objectID)
        #expect(Set(store.tags(for: imported).compactMap(\.name)) == ["Work", "Travel"])
        #expect(store.allTags().count == 2)

        // A second entry in the same unsaved batch reuses the new tag too.
        let next = makeEntry("Imported next.", in: context)
        ImportedTagMapper.apply(["TRAVEL"], to: next, in: context)
        #expect(store.allTags().count == 2)
        try context.save()
        #expect(store.tags(for: next).map(\.name) == ["Travel"])
    }

    // MARK: Helpers

    private func makeEntry(_ text: String, in context: NSManagedObjectContext) -> DiaryEntry {
        let entry = DiaryEntry(context: context)
        entry.id = UUID()
        entry.date = Date()
        entry.createdAt = Date()
        entry.updatedAt = Date()
        entry.text = text
        entry.isStarred = false
        return entry
    }
}
