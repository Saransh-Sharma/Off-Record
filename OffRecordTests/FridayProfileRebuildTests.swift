import CoreData
import Foundation
import Testing
@testable import OffRecord

/// Friday's profile is rebuilt from the journal, so it must count each entry
/// once and forget whatever an edit or delete removed.
@MainActor
@Suite(.serialized)
struct FridayProfileRebuildTests {

    @Test func learningCountsEachEntryOnce() {
        let engine = FridayAssistantEngine.makeScratch()
        engine.learn(from: [
            input("Dinner with Maya in Bangalore helped me feel grounded.", day: 1),
            input("A long walk after work cleared my head.", day: 2),
            input("Coffee with Maya before the trip.", day: 3),
        ])

        #expect(engine.behavioralPatterns.totalEntries == 3)
    }

    @Test(.enabled(if: NaturalLanguageAssets.tagsNames, "Needs Apple's name-tagging data"))
    func editedEntryForgetsTheOldName() {
        let id = UUID()
        let before = FridayAssistantEngine.makeScratch()
        before.learn(from: [input("Dinner with Maya in Bangalore helped me feel grounded.", day: 1, id: id)])
        #expect(before.knowledgeGraph.nodes["maya"] != nil)

        let after = FridayAssistantEngine.makeScratch()
        after.learn(from: [input("Dinner with Priya in Bangalore helped me feel grounded.", day: 1, id: id)])

        #expect(after.knowledgeGraph.nodes["maya"] == nil)
        #expect(after.knowledgeGraph.nodes["priya"] != nil)
        #expect(after.behavioralPatterns.totalEntries == 1)
    }

    @Test(.enabled(if: NaturalLanguageAssets.tagsNames, "Needs Apple's name-tagging data"))
    func deletedEntryLeavesNoTrace() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let maya = makeEntry("Dinner with Maya in Bangalore helped me feel grounded.", in: context)
        _ = makeEntry("A long walk after work cleared my head.", in: context)
        try context.save()

        let before = FridayAssistantEngine.makeScratch()
        before.learn(from: FridayProfileRebuilder.learningInputs(in: context))
        #expect(before.knowledgeGraph.nodes["maya"] != nil)
        #expect(before.behavioralPatterns.totalEntries == 2)

        context.delete(maya)
        try context.save()

        let after = FridayAssistantEngine.makeScratch()
        after.learn(from: FridayProfileRebuilder.learningInputs(in: context))
        #expect(after.knowledgeGraph.nodes["maya"] == nil)
        #expect(after.behavioralPatterns.totalEntries == 1)
    }

    @Test func rebuildIgnoresInputOrder() {
        let inputs = [
            input("Dinner with Maya in Bangalore helped me feel grounded.", day: 1),
            input("Work with Sam felt tense but we fixed the launch.", day: 2),
            input("Coffee with Maya before the trip to Goa.", day: 3),
        ]
        let first = FridayAssistantEngine.makeScratch()
        first.learn(from: inputs)
        let second = FridayAssistantEngine.makeScratch()
        second.learn(from: inputs.reversed())

        #expect(graphSignature(first) == graphSignature(second))
        #expect(first.behavioralPatterns.totalEntries == second.behavioralPatterns.totalEntries)
    }

    @Test func scratchEngineNeverReplacesTheSavedProfile() {
        let shared = FridayAssistantEngine.shared
        let entriesBefore = shared.behavioralPatterns.totalEntries
        let scratch = FridayAssistantEngine.makeScratch()
        scratch.learn(from: [input("Dinner with Maya in Bangalore.", day: 1)])

        #expect(shared.behavioralPatterns.totalEntries == entriesBefore)
    }

    @Test func fingerprintTracksEntriesAndEditsButNotOrder() {
        let a = (id: UUID(), updatedAt: Optional(Date(timeIntervalSince1970: 1_000)))
        let b = (id: UUID(), updatedAt: Optional(Date(timeIntervalSince1970: 2_000)))

        let base = FridayProfileFingerprint.make([a, b])
        #expect(base == FridayProfileFingerprint.make([b, a]))
        #expect(base != FridayProfileFingerprint.make([a]))
        #expect(base != FridayProfileFingerprint.make([a, (id: b.id, updatedAt: Optional(Date(timeIntervalSince1970: 2_001)))]))
    }

    @Test func learningInputSkipsEmptyAndHighRiskEntries() {
        let context = PersistenceController(inMemory: true).container.viewContext
        let normal = makeEntry("Lunch with Maya by the lake.", in: context)
        let empty = makeEntry("   ", in: context)
        let risky = makeEntry("I keep thinking about ending my life.", in: context)

        #expect(FridayLearningInput(entry: normal) != nil)
        #expect(FridayLearningInput(entry: empty) == nil)
        #expect(FridayLearningInput(entry: risky) == nil)
    }

    // MARK: Helpers

    private func input(_ text: String, day: Int, id: UUID = UUID()) -> FridayLearningInput {
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: day, hour: 20)) ?? Date()
        return FridayLearningInput(id: id, text: text, mood: Mood.calm.rawValue, date: date, duration: 0)
    }

    private func graphSignature(_ engine: FridayAssistantEngine) -> [String] {
        engine.knowledgeGraph.nodes.values
            .map { "\($0.id):\($0.mentions)" }
            .sorted()
    }

    private func makeEntry(_ text: String, in context: NSManagedObjectContext) -> DiaryEntry {
        let entry = DiaryEntry(context: context)
        entry.id = UUID()
        entry.date = Date()
        entry.createdAt = Date()
        entry.updatedAt = Date()
        entry.text = text
        return entry
    }
}
