import CoreData
import Foundation
import Testing
@testable import OffRecord

/// Friday's profile lives in a protected local file. The old CloudKit-synced
/// `AIState` row is read once, moved into the file, and deleted.
@MainActor
@Suite(.serialized)
struct FridayProfileStoreTests {

    @Test func legacySyncedRowMovesIntoTheLocalFileAndIsDeleted() throws {
        let (directory, cleanup) = try temporaryDirectory()
        defer { cleanup() }
        let context = PersistenceController(inMemory: true).container.viewContext
        try insertLegacyRow(type: "friday_assistant", payload: learnedPayload(), in: context)

        let store = FridayProfileStore(directoryURL: directory, legacyContext: context)
        let loaded = try #require(store.load())

        #expect(loaded.knowledgeGraph.nodes["maya"] != nil)
        #expect(FileManager.default.fileExists(atPath: store.file.url.path))
        #expect(try legacyRowCount(in: context) == 0)

        let values = try store.file.url.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)

        // Later loads read the file; nothing is left in synced storage.
        let reloaded = try #require(FridayProfileStore(directoryURL: directory, legacyContext: context).load())
        #expect(reloaded.knowledgeGraph.nodes["maya"] != nil)
    }

    @Test func oldDigitalTwinRowMovesToo() throws {
        let (directory, cleanup) = try temporaryDirectory()
        defer { cleanup() }
        let context = PersistenceController(inMemory: true).container.viewContext
        try insertLegacyRow(type: "digital_twin", payload: learnedPayload(), in: context)

        let loaded = FridayProfileStore(directoryURL: directory, legacyContext: context).load()

        #expect(loaded?.knowledgeGraph.nodes["maya"] != nil)
        #expect(try legacyRowCount(in: context) == 0)
    }

    @Test func rowSyncedInFromAnOlderDeviceIsDeletedAndTheFileWins() throws {
        let (directory, cleanup) = try temporaryDirectory()
        defer { cleanup() }
        let context = PersistenceController(inMemory: true).container.viewContext
        let store = FridayProfileStore(directoryURL: directory, legacyContext: context)
        store.save(learnedPayload())

        var stale = learnedPayload()
        stale.knowledgeGraph = PersonalKnowledgeGraph()
        try insertLegacyRow(type: "friday_assistant", payload: stale, in: context)

        let loaded = try #require(store.load())
        #expect(loaded.knowledgeGraph.nodes["maya"] != nil)
        #expect(try legacyRowCount(in: context) == 0)
    }

    @Test func deleteRemovesTheFileAndAnyLegacyRow() throws {
        let (directory, cleanup) = try temporaryDirectory()
        defer { cleanup() }
        let context = PersistenceController(inMemory: true).container.viewContext
        let store = FridayProfileStore(directoryURL: directory, legacyContext: context)
        store.save(learnedPayload())
        try insertLegacyRow(type: "friday_assistant", payload: learnedPayload(), in: context)

        store.delete()

        #expect(!FileManager.default.fileExists(atPath: store.file.url.path))
        #expect(try legacyRowCount(in: context) == 0)
        #expect(store.load() == nil)
    }

    @Test func emptyStoreLoadsNothing() throws {
        let (directory, cleanup) = try temporaryDirectory()
        defer { cleanup() }
        let context = PersistenceController(inMemory: true).container.viewContext

        #expect(FridayProfileStore(directoryURL: directory, legacyContext: context).load() == nil)
    }

    // MARK: Helpers

    /// A profile that knows Maya, built directly so it doesn't depend on the name tagger.
    private func learnedPayload() -> FridayProfilePayload {
        let engine = FridayAssistantEngine.makeScratch()
        engine.learn(FridayLearningInput(id: UUID(), text: "Dinner with Maya in Bangalore helped me feel grounded.", mood: "calm", date: Date(), duration: 0))
        var graph = engine.knowledgeGraph
        graph.addOrUpdate(id: "maya", label: "Maya", type: .person, sentiment: 0.4)
        return FridayProfilePayload(
            communicationStyle: engine.communicationStyle,
            emotionalSignature: engine.emotionalSignature,
            thoughtPatterns: engine.thoughtPatterns,
            knowledgeGraph: graph,
            behavioralPatterns: engine.behavioralPatterns,
            summary: engine.summary
        )
    }

    private func insertLegacyRow(type: String, payload: FridayProfilePayload, in context: NSManagedObjectContext) throws {
        let state = AIState(context: context)
        state.id = UUID()
        state.type = type
        state.payload = try JSONEncoder().encode(payload)
        state.updatedAt = Date()
        try context.save()
    }

    private func legacyRowCount(in context: NSManagedObjectContext) throws -> Int {
        let request = NSFetchRequest<AIState>(entityName: "AIState")
        request.predicate = NSPredicate(format: "type IN %@", FridayProfileStore.legacyStateTypes)
        return try context.count(for: request)
    }

    private func temporaryDirectory() throws -> (URL, () -> Void) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("friday-profile-\(UUID().uuidString)", isDirectory: true)
        return (url, { try? FileManager.default.removeItem(at: url) })
    }
}
