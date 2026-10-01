import CoreData
import Foundation
import JournalFoundation
import Testing
@testable import OffRecord

/// "Keep Out of Friday" is enforced at every AI gate: the search index,
/// Friday's evidence and profile, proactive cards, saved chat, and Weekly
/// Reflection (which counts kept-out entries but never quotes them).
@MainActor
@Suite(.serialized)
struct AIExclusionGateTests {

    // MARK: Search index

    @Test func indexSkipsEntriesKeptOutOfFriday() {
        let context = PersistenceController(inMemory: true).container.viewContext
        let included = makeEntry("Dinner with Maya by the lake.", in: context)
        let keptOut = makeEntry("Dinner with Maya by the lake.", exclusion: .excludedFromAI, in: context)
        let leftOut = makeEntry("Dinner with Maya by the lake.", exclusion: .excludedFromAIAndReflection, in: context)

        #expect(IndexableEntry(entry: included) != nil)
        #expect(IndexableEntry(entry: keptOut) == nil)
        #expect(IndexableEntry(entry: leftOut) == nil)
    }

    // MARK: Friday evidence

    @Test func fridayNeverCitesEntriesKeptOutOfHer() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let included = makeEntry("Work pressure was heavy after the meeting.", in: context)
        let keptOut = makeEntry("Work pressure and the meeting again.", exclusion: .excludedFromAI, in: context)

        #expect(EvidenceFridayEngine.citableEntries([included, keptOut]).map(\.id) == [included.id])

        let evidence = [
            evidence(for: keptOut, "Work pressure and the meeting again.", score: 0.05),
            evidence(for: included, "Work pressure was heavy after the meeting.", score: 0.04),
        ]
        let citable = EvidenceFridayEngine.citableEvidence(evidence, from: [included, keptOut])
        #expect(citable.map(\.entryID) == [try #require(included.id)])
    }

    // MARK: Friday's profile

    @Test func fridayLearnsNothingFromEntriesKeptOutOfHer() async throws {
        let container = PersistenceController(inMemory: true).container
        let context = container.viewContext
        let included = makeEntry("Dinner with Maya in Bangalore helped me feel grounded.", in: context)
        let keptOut = makeEntry("Coffee with Priya before the trip.", in: context)
        try context.save()

        #expect(FridayLearningInput(entry: keptOut) != nil)
        let before = await FridayProfileRebuilder.currentFingerprint(container: container)

        keptOut.journalAIExclusion = .excludedFromAI
        try context.save()

        #expect(FridayLearningInput(entry: keptOut) == nil)
        #expect(FridayProfileRebuilder.learningInputs(in: context).map(\.id) == [try #require(included.id)])
        let after = await FridayProfileRebuilder.currentFingerprint(container: container)
        #expect(after != before)
        #expect(after == FridayProfileFingerprint.make([(id: try #require(included.id), updatedAt: included.updatedAt)]))

        let engine = FridayAssistantEngine.makeScratch()
        engine.learn(from: FridayProfileRebuilder.learningInputs(in: context))
        #expect(engine.behavioralPatterns.totalEntries == 1)
        #expect(engine.knowledgeGraph.nodes["priya"] == nil)
    }

    // MARK: Proactive cards

    @Test func proactiveAnalysisSkipsEntriesKeptOutOfFriday() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let included = makeEntry("Lunch with Maya by the lake.", in: context)
        let keptOut = makeEntry("Thinking about the job offer.", exclusion: .excludedFromAI, in: context)
        let leftOut = makeEntry("Thinking about moving.", exclusion: .excludedFromAIAndReflection, in: context)

        let ids = ProactiveReflectionController.analyzableSnapshots([included, keptOut, leftOut]).map(\.id)

        #expect(ids == [try #require(included.id)])
    }

    // MARK: Weekly Reflection snapshot

    @Test func weeklySnapshotCountsKeptOutEntriesWithoutTheirText() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let keptOut = makeEntry("Maya and I argued about the move to Pune.", exclusion: .excludedFromAI, in: context)
        keptOut.mood = Mood.sad.rawValue
        let leftOut = makeEntry("Left out entirely.", exclusion: .excludedFromAIAndReflection, in: context)
        let included = makeEntry("Quiet walk after work.", in: context)

        let snapshot = try #require(WeeklyReflectionEntrySnapshot(entry: keptOut))
        #expect(snapshot.text.isEmpty)
        #expect(snapshot.wordCount == 9)
        #expect(snapshot.mood == Mood.sad.rawValue)
        #expect(snapshot.aiExclusion == .excludedFromAI)
        #expect(snapshot.sentiment < 0)

        #expect(WeeklyReflectionEntrySnapshot(entry: leftOut) == nil)
        #expect(WeeklyReflectionEntrySnapshot(entry: included)?.text == "Quiet walk after work.")
    }

    // MARK: Weekly Reflection generation

    @Test func keptOutEntriesCountButAreNeverQuotedOrThemed() throws {
        let now = try midweekNoon()
        let period = WeeklyReflectionEligibilityService.period(containing: now)
        let readable = [
            snapshot(daysAgo: 0, text: gardenText, now: now),
            snapshot(daysAgo: 1, text: gardenText, now: now),
        ]
        let keptOut = snapshot(daysAgo: 2, text: secretText, exclusion: .excludedFromAI, now: now)
        let leftOut = snapshot(daysAgo: 2, text: secretText, exclusion: .excludedFromAIAndReflection, now: now)

        let report = WeeklyReflectionGenerationService.generate(period: period, entries: readable + [keptOut, leftOut], now: now)

        #expect(report.status == .ready)
        #expect(report.privateEntryCount == 1)
        #expect(report.includedEntryIds.contains(keptOut.id))
        #expect(!report.includedEntryIds.contains(leftOut.id))
        #expect(report.summary.contains("3 entries"))
        #expect(report.summary.contains("kept out of Friday"))
        let refs = report.themes.flatMap(\.evidenceRefs)
        #expect(!refs.isEmpty)
        #expect(refs.allSatisfy { $0.entryId != keptOut.id && $0.entryId != leftOut.id })
        let generated = ([report.heroSentence, report.summary] + report.wins + report.frictions + report.questions
            + report.themes.map(\.title) + refs.compactMap(\.quote)).joined(separator: " ").lowercased()
        #expect(!generated.contains("pune"))
        #expect(!generated.contains("lawyer"))
    }

    @Test func weekOfOnlyKeptOutEntriesReportsTotalsOnly() throws {
        let now = try midweekNoon()
        let period = WeeklyReflectionEligibilityService.period(containing: now)
        let entries = (0..<3).map { snapshot(daysAgo: $0, text: secretText, exclusion: .excludedFromAI, now: now) }

        let report = WeeklyReflectionGenerationService.generate(period: period, entries: entries, now: now)

        #expect(report.status == .ready)
        #expect(report.eligibility != .empty)
        #expect(report.privateEntryCount == 3)
        #expect(report.themes.isEmpty)
        #expect(report.includedEntryIds.count == 3)
        #expect(WeeklyReflectionGenerationService.validate(report))
        #expect(!report.summary.lowercased().contains("pune"))
        #expect(report.summary.contains("kept out of Friday"))
    }

    @Test func leftOutEntriesAreInvisible() throws {
        let now = try midweekNoon()
        let period = WeeklyReflectionEligibilityService.period(containing: now)
        let entries = (0..<3).map { snapshot(daysAgo: $0, text: secretText, exclusion: .excludedFromAIAndReflection, now: now) }

        let report = WeeklyReflectionGenerationService.generate(period: period, entries: entries, now: now)

        #expect(report.status == .insufficientData)
        #expect(report.includedEntryIds.isEmpty)
        #expect(report.privateEntryCount == 0)
    }

    @Test func leftOutEntriesAreNotReportedAsDeleted() throws {
        let now = try midweekNoon()
        let period = WeeklyReflectionEligibilityService.period(containing: now)
        let first = snapshot(daysAgo: 0, text: gardenText, now: now)
        let second = snapshot(daysAgo: 1, text: gardenText, now: now)
        let previous = WeeklyReflectionGenerationService.generate(period: period, entries: [first, second], now: now)
        #expect(previous.includedEntryIds.contains(second.id))

        // The second entry is now left out of Weekly Reflection, so its snapshot is gone.
        let next = WeeklyReflectionGenerationService.generate(
            period: period,
            entries: [first],
            previousVersion: previous,
            leftOutEntryIds: [second.id],
            now: now
        )
        #expect(next.unavailableEntryIds.isEmpty)
        #expect(!next.includedEntryIds.contains(second.id))
    }

    @Test func keepingAnEntryOutChangesTheWeeklySignature() throws {
        let now = try midweekNoon()
        let id = UUID()
        let included = WeeklyReflectionEntrySnapshot(id: id, date: now, updatedAt: now, mood: nil, text: gardenText, sourceType: .text)
        let keptOut = WeeklyReflectionEntrySnapshot(id: id, date: now, updatedAt: now, mood: nil, text: gardenText, sourceType: .text, aiExclusion: .excludedFromAI)
        let leftOut = WeeklyReflectionEntrySnapshot(id: id, date: now, updatedAt: now, mood: nil, text: gardenText, sourceType: .text, aiExclusion: .excludedFromAIAndReflection)

        let signature = WeeklyReflectionGenerationService.inputSignature(for: [included])
        #expect(signature == "\(id.uuidString):\(now.timeIntervalSinceReferenceDate):\(included.wordCount)#hidden:")
        #expect(WeeklyReflectionGenerationService.inputSignature(for: [keptOut]) != signature)
        #expect(WeeklyReflectionGenerationService.inputSignature(for: [leftOut]) == WeeklyReflectionGenerationService.inputSignature(for: []))
    }

    @Test func savedReportsForgetQuotesFromAnEntryKeptOut() throws {
        let now = try midweekNoon()
        let period = WeeklyReflectionEligibilityService.period(containing: now)
        let first = snapshot(daysAgo: 0, text: gardenText, now: now)
        let second = snapshot(daysAgo: 1, text: gardenText, now: now)
        let report = WeeklyReflectionGenerationService.generate(period: period, entries: [first, second], now: now)
        #expect(report.themes.flatMap(\.evidenceRefs).contains { $0.entryId == second.id })

        let context = PersistenceController(inMemory: true).container.viewContext
        let repository = WeeklyReflectionRepository(context: context)
        try repository.save(settings: .default, reports: [report])
        let controller = WeeklyReflectionController(repository: repository)

        controller.forgetQuotes(fromEntryID: second.id)

        let stored = try #require(repository.load().reports.first)
        #expect(!stored.themes.flatMap(\.evidenceRefs).contains { $0.entryId == second.id })
        #expect(stored.themes.flatMap(\.evidenceRefs).contains { $0.entryId == first.id })
    }

    // MARK: Saved chat

    @Test func savedChatDropsCitationsFromEntriesKeptOut() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let included = makeEntry("Work pressure was heavy after the meeting.", in: context)
        let keptOut = makeEntry("Work pressure and the meeting again.", exclusion: .excludedFromAI, in: context)
        let entries = [included, keptOut]
        let answer = FridayChatMessage(
            id: UUID(),
            timestamp: Date(),
            summary: "2 entries mention work.",
            isUser: false,
            evidence: [
                evidence(for: included, "Work pressure was heavy after the meeting.", score: 0.04),
                evidence(for: keptOut, "Work pressure and the meeting again.", score: 0.05),
            ],
            observations: [
                EvidenceObservation(text: "The clearest example: “Work pressure and the meeting again.”", evidenceIDs: ["chunk-\(keptOut.id!.uuidString)"]),
            ],
            confidence: 0.6,
            limitations: nil,
            followUps: [],
            needsSupport: false
        )
        defer { FridayChatHistoryStore.clear() }
        FridayChatHistoryStore.save([answer])

        let restored = try #require(FridayChatHistoryStore.load { id in entries.first { $0.id == id } }.first)

        #expect(restored.evidence.map(\.entryID) == [try #require(included.id)])
        #expect(restored.observations.isEmpty)
        #expect(restored.limitations?.contains("kept out of Friday") == true)
    }

    // MARK: Helpers

    private var gardenText: String {
        String(repeating: "garden tomatoes watering evening sunlight neighbours ", count: 20)
    }

    private var secretText: String {
        String(repeating: "Pune lawyer contract custody hearing ", count: 25)
    }

    private func midweekNoon() throws -> Date {
        let date = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: 27, hour: 12)))
        #expect(Calendar.current.component(.weekday, from: date) == 4)
        return date
    }

    private func snapshot(daysAgo: Int, text: String, exclusion: JournalAIExclusion = .included, now: Date) -> WeeklyReflectionEntrySnapshot {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: now) ?? now
        return WeeklyReflectionEntrySnapshot(
            id: UUID(),
            date: date,
            updatedAt: date,
            mood: Mood.calm.rawValue,
            text: text,
            sourceType: .text,
            aiExclusion: exclusion
        )
    }

    private func evidence(for entry: DiaryEntry, _ text: String, score: Double) -> EvidenceReference {
        EvidenceReference(
            id: "chunk-\(entry.id!.uuidString)",
            entryID: entry.id!,
            date: entry.date ?? Date(),
            mood: nil,
            snippet: text,
            chunkText: text,
            score: score,
            matchReason: .exact
        )
    }

    private func makeEntry(_ text: String, exclusion: JournalAIExclusion = .included, in context: NSManagedObjectContext) -> DiaryEntry {
        let entry = DiaryEntry(context: context)
        let now = Date()
        entry.id = UUID()
        entry.date = now
        entry.createdAt = now
        entry.updatedAt = now
        entry.text = text
        entry.journalAIExclusion = exclusion
        return entry
    }
}
