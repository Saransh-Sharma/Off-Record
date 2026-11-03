import CoreData
import Foundation
import JournalFoundation
import Testing
@testable import OffRecord

/// Person, place, and topic pages in My World: mentions by month, mood when
/// mentioned, first and last mention, the safety and Keep Out of Friday gates,
/// and Rename and Forget.
@MainActor
@Suite(.serialized)
struct KnowledgePageTests {

    // MARK: Aggregation

    @Test func mentionsAreCountedByMonthWithEmptyMonthsFilledIn() {
        let inputs = [
            input("Coffee with Maya. Maya brought her sister.", on: date(month: 1, day: 10), mood: "happy"),
            input("Called Maya after work.", on: date(month: 1, day: 20), mood: "calm"),
            input("Maya’s birthday dinner.", on: date(month: 3, day: 5), mood: "happy"),
            input("Lunch with Mayank.", on: date(month: 2, day: 2)),
            input("maybe maya will call", on: date(month: 2, day: 8))
        ]

        let summary = KnowledgeMentionAggregator.summarize(label: "Maya", type: .person, inputs: inputs, now: date(month: 3, day: 15))

        #expect(summary.entryCount == 3)
        #expect(summary.mentions.map(\.occurrences) == [1, 1, 2])
        #expect(summary.firstMention == date(month: 1, day: 10))
        #expect(summary.lastMention == date(month: 3, day: 5))
        #expect(summary.months.map(\.count) == [2, 0, 1])
        #expect(summary.months.first?.month == date(month: 1, day: 1, hour: 0))
        #expect(summary.busiestMonth?.month == date(month: 1, day: 1, hour: 0))
    }

    @Test func moodWhenMentionedSkipsEntriesWithoutAMood() {
        let inputs = [
            input("Goa trip with Arjun.", on: date(month: 2, day: 1), mood: "happy"),
            input("Arjun called.", on: date(month: 2, day: 2), mood: "happy"),
            input("Arjun was late.", on: date(month: 2, day: 3), mood: "anxious"),
            input("Arjun again.", on: date(month: 2, day: 4), mood: nil),
            input("Arjun, briefly.", on: date(month: 2, day: 5), mood: "none")
        ]

        let summary = KnowledgeMentionAggregator.summarize(label: "Arjun", type: .person, inputs: inputs, now: date(month: 2, day: 10))

        #expect(summary.entryCount == 5)
        #expect(summary.moods.map(\.mood) == [.happy, .anxious])
        #expect(summary.moods.map(\.count) == [2, 1])
    }

    @Test func topicsMatchInAnyCaseButOnlyWholeWords() {
        let inputs = [
            input("Work was long today.", on: date(month: 4, day: 1)),
            input("After work I walked.", on: date(month: 4, day: 2)),
            input("Homework with the kids.", on: date(month: 4, day: 3))
        ]

        let summary = KnowledgeMentionAggregator.summarize(label: "Work", type: .topic, inputs: inputs, now: date(month: 4, day: 5))

        #expect(summary.entryCount == 2)
    }

    @Test func theChartShowsAtMostTwelveMonthsEndingNow() {
        let inputs = (0..<20).map { offset in
            input("Saw Leo.", on: Calendar.current.date(byAdding: .month, value: -offset, to: date(month: 6, day: 10)) ?? Date())
        }

        let summary = KnowledgeMentionAggregator.summarize(label: "Leo", type: .person, inputs: inputs, now: date(month: 6, day: 20))

        #expect(summary.entryCount == 20)
        #expect(summary.months.count == KnowledgeMentionAggregator.chartMonths)
        #expect(summary.months.last?.month == date(month: 6, day: 1, hour: 0))
        #expect(summary.months.allSatisfy { $0.count == 1 })
    }

    @Test func theSnippetIsTheSentenceWithTheMention() {
        let text = "Long morning at the office. Then lunch with Maya by the lake. Home early."
        let range = try! #require(text.range(of: "Maya"))

        #expect(KnowledgeMentionAggregator.snippet(in: text, around: range) == "Then lunch with Maya by the lake.")
    }

    // MARK: Gates

    @Test func pagesLeaveOutKeptOutAndHighRiskEntries() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let readable = makeEntry("Dinner with Maya by the lake.", on: date(month: 5, day: 1), in: context)
        let keptOut = makeEntry("Long talk with Maya about money.", on: date(month: 5, day: 2), exclusion: .excludedFromAI, in: context)
        let keptOutOfEverything = makeEntry("Maya and I argued.", on: date(month: 5, day: 3), exclusion: .excludedFromAIAndReflection, in: context)
        let risky = makeEntry("After Maya left I thought about ending my life.", on: date(month: 5, day: 4), in: context)
        let node = PersonalKnowledgeGraph.KnowledgeNode(id: "maya", label: "Maya", type: .person, mentions: 4, firstSeen: Date(), lastSeen: Date())

        let content = try #require(KnowledgeMentionAggregator.content(
            for: node,
            entries: [readable, keptOut, keptOutOfEverything, risky],
            isForgotten: false,
            alias: nil,
            now: date(month: 5, day: 10)
        ))

        let ids = content.summary.mentions.map(\.entryID)
        #expect(ids == [try #require(readable.id)])
        #expect(!content.summary.mentions.contains { $0.snippet.contains("ending my life") })
        #expect(content.summary.months.map(\.count).reduce(0, +) == 1)
    }

    @Test func aForgottenItemHasNoPageContent() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let entry = makeEntry("Dinner with Maya.", on: date(month: 5, day: 1), in: context)
        let node = PersonalKnowledgeGraph.KnowledgeNode(id: "maya", label: "Maya", type: .person, firstSeen: Date(), lastSeen: Date())

        #expect(KnowledgeMentionAggregator.content(for: node, entries: [entry], isForgotten: true, alias: nil) == nil)
    }

    @Test func aRenameChangesTheTitleButEntriesAreFoundByTheWrittenName() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let written = makeEntry("Dinner with Maya.", on: date(month: 5, day: 1), in: context)
        _ = makeEntry("Mia from work said hi.", on: date(month: 5, day: 2), in: context)
        let node = PersonalKnowledgeGraph.KnowledgeNode(id: "maya", label: "Maya", type: .person, firstSeen: Date(), lastSeen: Date())
        let entries = try context.fetch(NSFetchRequest<DiaryEntry>(entityName: "DiaryEntry"))

        let content = try #require(KnowledgeMentionAggregator.content(for: node, entries: entries, isForgotten: false, alias: " Mia "))

        #expect(content.title == "Mia")
        #expect(content.writtenAs == "Maya")
        #expect(content.summary.mentions.map(\.entryID) == [try #require(written.id)])

        let unrenamed = try #require(KnowledgeMentionAggregator.content(for: node, entries: entries, isForgotten: false, alias: ""))
        #expect(unrenamed.title == "Maya")
        #expect(unrenamed.writtenAs == nil)
    }

    @Test func memoryPreferencesDriveRenameAndForget() throws {
        let preferences = FridayMemoryPreferences.shared
        let savedForgotten = preferences.forgottenIDs
        let savedAliases = preferences.aliases
        defer {
            preferences.reset()
            for id in savedForgotten {
                preferences.forget(PersonalKnowledgeGraph.KnowledgeNode(id: id, label: id, type: .topic, firstSeen: Date(), lastSeen: Date()))
            }
            for (id, alias) in savedAliases {
                preferences.rename(PersonalKnowledgeGraph.KnowledgeNode(id: id, label: "", type: .topic, firstSeen: Date(), lastSeen: Date()), to: alias)
            }
        }
        let context = PersistenceController(inMemory: true).container.viewContext
        let entry = makeEntry("Walked with Rohan.", on: date(month: 5, day: 1), in: context)
        let node = PersonalKnowledgeGraph.KnowledgeNode(id: "rohan-page-test", label: "Rohan", type: .person, firstSeen: Date(), lastSeen: Date())

        preferences.rename(node, to: "Ro")
        let renamed = try #require(KnowledgeMentionAggregator.content(
            for: node, entries: [entry], isForgotten: preferences.isForgotten(node), alias: preferences.aliases[node.id]
        ))
        #expect(renamed.title == "Ro")
        #expect(renamed.summary.entryCount == 1)

        preferences.forget(node)
        #expect(KnowledgeMentionAggregator.content(
            for: node, entries: [entry], isForgotten: preferences.isForgotten(node), alias: preferences.aliases[node.id]
        ) == nil)
    }

    // MARK: Helpers

    private func input(_ text: String, on date: Date, mood: String? = nil) -> FridayLearningInput {
        FridayLearningInput(id: UUID(), text: text, mood: mood, date: date, duration: 0)
    }

    private func makeEntry(
        _ text: String,
        on date: Date,
        exclusion: JournalAIExclusion = .included,
        in context: NSManagedObjectContext
    ) -> DiaryEntry {
        let entry = DiaryEntry(context: context)
        entry.id = UUID()
        entry.date = date
        entry.createdAt = date
        entry.updatedAt = date
        entry.text = text
        entry.isStarred = false
        entry.journalAIExclusion = exclusion
        return entry
    }

    private func date(month: Int, day: Int, hour: Int = 12) -> Date {
        var components = DateComponents()
        components.calendar = Calendar.current
        components.year = 2026
        components.month = month
        components.day = day
        components.hour = hour
        return Calendar.current.date(from: components) ?? Date()
    }
}
