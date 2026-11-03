import CoreData
import Foundation
import JournalFoundation
import Testing
@testable import OffRecord

/// Model "OffRecord 3": AI exclusion, tags, and journals, plus the lightweight
/// migration from "OffRecord 2" and the rules CloudKit mirroring needs.
@MainActor
@Suite(.serialized)
struct JournalModelV3Tests {

    // MARK: Migration

    @Test func version2StoreOpensWithCurrentModel() throws {
        let momdURL = try #require(Bundle.main.url(forResource: "OffRecord", withExtension: "momd"))
        let version2 = try #require(NSManagedObjectModel(contentsOf: momdURL.appendingPathComponent("OffRecord 2.mom")))
        // Plain objects, so this copy of the model doesn't compete with the app's for DiaryEntry.
        for entity in version2.entities {
            entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        }
        #expect(version2.entitiesByName["DiaryEntry"]?.attributesByName["aiExclusion"] == nil)
        #expect(version2.entitiesByName["Tag"] == nil)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("model-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("OffRecord.sqlite")

        let entryID = UUID()
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        do {
            let coordinator = NSPersistentStoreCoordinator(managedObjectModel: version2)
            let store = try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL, options: nil)
            let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
            context.persistentStoreCoordinator = coordinator
            let entry = NSEntityDescription.insertNewObject(forEntityName: "DiaryEntry", into: context)
            entry.setValue(entryID, forKey: "id")
            entry.setValue(date, forKey: "date")
            entry.setValue(date, forKey: "createdAt")
            entry.setValue(date, forKey: "updatedAt")
            entry.setValue("Dinner with Maya by the lake.", forKey: "text")
            entry.setValue("happy", forKey: "mood")
            try context.save()
            try coordinator.remove(store)
        }

        let current = try #require(NSManagedObjectModel(contentsOf: momdURL))
        #expect(current.entitiesByName["Tag"] != nil)
        #expect(current.entitiesByName["Journal"] != nil)
        #expect(!current.isConfiguration(withName: nil, compatibleWithStoreMetadata: try NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: NSSQLiteStoreType, at: storeURL, options: nil)))

        let container = NSPersistentContainer(name: "OffRecordMigrationTest", managedObjectModel: current)
        let description = NSPersistentStoreDescription(url: storeURL)
        description.shouldAddStoreAsynchronously = false
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        #expect(loadError == nil)

        let context = container.viewContext
        let request = NSFetchRequest<DiaryEntry>(entityName: "DiaryEntry")
        let entries = try context.fetch(request)
        let migrated = try #require(entries.first)
        #expect(entries.count == 1)
        #expect(migrated.id == entryID)
        #expect(migrated.text == "Dinner with Maya by the lake.")
        #expect(migrated.aiExclusion == nil)
        #expect(migrated.journalAIExclusion == .included)
        #expect((migrated.tags?.count ?? 0) == 0)
        #expect(migrated.journal == nil)

        // The new parts work on the migrated store.
        let tag = try TagStore(context: context).createTag(named: "Family")
        try TagStore(context: context).assign(tag, to: migrated)
        let journal = try JournalStore(context: context).createJournal(named: "Travel")
        try JournalStore(context: context).assign(migrated, to: journal)
        migrated.journalAIExclusion = .excludedFromAI
        try context.save()
        #expect(TagStore(context: context).tags(for: migrated).map(\.name) == ["Family"])
        #expect(migrated.journal?.name == "Travel")
        #expect(migrated.aiExclusion == JournalAIExclusion.excludedFromAI.rawValue)
    }

    /// NSPersistentCloudKitContainer refuses models that break these rules.
    @Test func currentModelFollowsCloudKitRules() throws {
        let model = PersistenceController(inMemory: true).container.managedObjectModel
        for entity in model.entities {
            #expect(entity.uniquenessConstraints.isEmpty, "\(entity.name ?? "") has a unique constraint")
            for attribute in entity.attributesByName.values {
                #expect(attribute.isOptional || attribute.defaultValue != nil, "\(entity.name ?? "").\(attribute.name) needs to be optional or defaulted")
            }
            for relationship in entity.relationshipsByName.values {
                #expect(relationship.isOptional, "\(entity.name ?? "").\(relationship.name) must be optional")
                #expect(relationship.inverseRelationship != nil, "\(entity.name ?? "").\(relationship.name) needs an inverse")
                #expect(relationship.deleteRule != .denyDeleteRule, "\(entity.name ?? "").\(relationship.name) can't deny deletes")
            }
        }
        let entry = try #require(model.entitiesByName["DiaryEntry"])
        #expect(entry.relationshipsByName["tags"]?.isToMany == true)
        #expect(entry.relationshipsByName["tags"]?.inverseRelationship?.isToMany == true)
        #expect(entry.relationshipsByName["journal"]?.isToMany == false)
        #expect(entry.relationshipsByName["journal"]?.inverseRelationship?.name == "entries")
        #expect(model.entitiesByName["Journal"]?.attributesByName["isArchived"]?.defaultValue as? Bool == false)
    }

    // MARK: AI exclusion storage

    @Test func exclusionDefaultsToIncludedAndStoresRawValues() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let entry = makeEntry("Lunch with Maya.", in: context)
        #expect(entry.journalAIExclusion == .included)
        #expect(entry.aiExclusion == nil)

        let before = try #require(entry.updatedAt)
        entry.journalAIExclusion = .excludedFromAIAndReflection
        #expect(entry.aiExclusion == "excludedFromAIAndReflection")
        #expect(try #require(entry.updatedAt) > before)

        entry.journalAIExclusion = .included
        #expect(entry.aiExclusion == nil)

        entry.aiExclusion = "somethingNewer"
        #expect(entry.journalAIExclusion == .included)
    }

    @Test func permitsAssistantEvidencePredicateMatchesIncludedEntries() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let included = makeEntry("Included.", in: context)
        let excluded = makeEntry("Excluded.", in: context)
        let hidden = makeEntry("Hidden.", in: context)
        excluded.journalAIExclusion = .excludedFromAI
        hidden.journalAIExclusion = .excludedFromAIAndReflection
        try context.save()

        let request: NSFetchRequest<DiaryEntry> = DiaryEntry.fetchRequest()
        request.predicate = DiaryEntry.permitsAssistantEvidencePredicate
        #expect(try context.fetch(request).map(\.id) == [included.id])
    }

    // MARK: Tags

    @Test func tagsCreateRenameAssignAndDelete() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let store = TagStore(context: context)
        let entry = makeEntry("Dinner with Maya.", in: context)
        let other = makeEntry("Walk by the lake.", in: context)

        let family = try store.createTag(named: "  Family ")
        #expect(family.name == "Family")
        #expect(family.id != nil)
        #expect(try store.createTag(named: "family").objectID == family.objectID)
        #expect(throws: JournalOrganizationError.emptyName) { try store.createTag(named: "   ") }

        let walks = try store.createTag(named: "Walks")
        try store.assign(family, to: entry)
        try store.assign(walks, to: entry)
        try store.assign(walks, to: other)
        #expect(store.tags(for: entry).map(\.name) == ["Family", "Walks"])
        #expect(walks.entries?.count == 2)

        #expect(throws: JournalOrganizationError.duplicateName) { try store.rename(walks, to: "FAMILY") }
        try store.rename(walks, to: "Outside")
        #expect(store.allTags().map(\.name) == ["Family", "Outside"])

        try store.remove(family, from: entry)
        #expect(store.tags(for: entry).map(\.name) == ["Outside"])

        try store.delete(walks)
        #expect(store.allTags().map(\.name) == ["Family"])
        #expect(store.tags(for: other).isEmpty)
        #expect(!entry.isDeleted && !other.isDeleted)
    }

    // MARK: Journals

    @Test func journalsCreateRenameAssignArchiveAndDelete() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let store = JournalStore(context: context)
        let entry = makeEntry("Packed for the trip.", in: context)
        _ = makeEntry("Ordinary Tuesday.", in: context)

        let travel = try store.createJournal(named: "Travel", iconName: "airplane", colorName: "sky")
        let work = try store.createJournal(named: "Work")
        #expect(travel.sortOrder == 0)
        #expect(work.sortOrder == 1)
        #expect(travel.isArchived == false)
        #expect(throws: JournalOrganizationError.emptyName) { try store.createJournal(named: "") }

        try store.assign(entry, to: travel)
        #expect(store.entries(in: travel).map(\.id) == [entry.id])
        #expect(store.entries(in: nil).count == 1)

        try store.rename(travel, to: "Trips")
        #expect(store.journals().map(\.name) == ["Trips", "Work"])

        try store.setArchived(work, true)
        #expect(store.journals().map(\.name) == ["Trips"])
        #expect(store.journals(includingArchived: true).count == 2)

        try store.delete(travel)
        #expect(entry.journal == nil)
        #expect(!entry.isDeleted)
        #expect(store.entries(in: nil).count == 2)

        try store.assign(entry, to: nil)
        #expect(entry.journal == nil)
    }

    // MARK: Helpers

    private func makeEntry(_ text: String, in context: NSManagedObjectContext) -> DiaryEntry {
        let entry = DiaryEntry(context: context)
        let now = Date()
        entry.id = UUID()
        entry.date = now
        entry.createdAt = now
        entry.updatedAt = now.addingTimeInterval(-60)
        entry.text = text
        return entry
    }
}
