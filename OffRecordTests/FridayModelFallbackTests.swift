import Foundation
import JournalFoundation
import Testing
@testable import OffRecord

/// Every on-device model path falls back to its deterministic text, and
/// heavy or high-risk input never reaches the model. Mocks stand in for the
/// model, so these run the same with or without Apple Intelligence.
@MainActor
@Suite(.serialized)
struct FridayModelFallbackTests {
    private let lunch = "Lunch with Maya by the lake. We talked about her new job in Lisbon and the move in spring, and it felt good to plan ahead together."
    private let heavy = "Work left me overwhelmed again and I could barely think about the review with my manager."
    private let risky = "Some nights I keep thinking about ending my life when the review goes badly at work."

    // MARK: Go Deeper

    @Test func goDeeperUsesAValidModelQuestionAndCachesIt() async {
        let generator = MockQuestionGenerator(reply: "What did Maya say about the job in Lisbon?")
        let provider = GoDeeperQuestionProvider(generator: generator, store: memoryStore(), isModelAvailable: { true })

        let first = await provider.firstQuestion(text: lunch, mood: .happy)
        let reopened = await provider.firstQuestion(text: lunch, mood: .happy)

        #expect(first == "What did Maya say about the job in Lisbon?")
        #expect(reopened == first)
        #expect(generator.calls == 1)
    }

    @Test func goDeeperFallsBackToTemplatesWhenTheModelFails() async {
        let invalid = MockQuestionGenerator(reply: "What did Priya think of your journey?")
        let throwing = MockQuestionGenerator(reply: nil, throws: true)
        let unavailable = MockQuestionGenerator(reply: "What did Maya say about the job in Lisbon?")
        let template = EntryFollowUpQuestion.make(text: lunch, mood: .happy)

        let invalidProvider = GoDeeperQuestionProvider(generator: invalid, store: memoryStore(), isModelAvailable: { true })
        #expect(await invalidProvider.firstQuestion(text: lunch, mood: .happy) == template)
        // The failed answer is remembered, so reopening shows the same template without asking again.
        #expect(await invalidProvider.firstQuestion(text: lunch, mood: .happy) == template)
        #expect(invalid.calls == 1)

        let throwingProvider = GoDeeperQuestionProvider(generator: throwing, store: memoryStore(), isModelAvailable: { true })
        #expect(await throwingProvider.firstQuestion(text: lunch, mood: .happy) == template)

        let offProvider = GoDeeperQuestionProvider(generator: unavailable, store: memoryStore(), isModelAvailable: { false })
        #expect(await offProvider.firstQuestion(text: lunch, mood: .happy) == template)
        #expect(unavailable.calls == 0)

        let excludedProvider = GoDeeperQuestionProvider(generator: unavailable, store: memoryStore(), isModelAvailable: { true })
        #expect(await excludedProvider.firstQuestion(text: lunch, mood: .happy, allowsModel: false) == template)
        #expect(unavailable.calls == 0)

        let noModel = GoDeeperQuestionProvider(generator: nil, store: memoryStore(), isModelAvailable: { true })
        #expect(await noModel.firstQuestion(text: lunch, mood: .happy) == template)
    }

    @Test func goDeeperNeverAsksAboutHeavyOrHighRiskEntries() async {
        let generator = MockQuestionGenerator(reply: "What did the review with your manager change?")
        let provider = GoDeeperQuestionProvider(generator: generator, store: memoryStore(), isModelAvailable: { true })

        #expect(JournalRiskClassifier.responseMode(for: heavy) == .gentle)
        #expect(await provider.firstQuestion(text: heavy, mood: .anxious) == nil)
        #expect(provider.nextQuestion(text: heavy, mood: .anxious, excluding: nil) == nil)
        #expect(await provider.firstQuestion(text: risky, mood: .sad) == nil)
        #expect(generator.calls == 0)
    }

    @Test func anotherQuestionNeverRepeatsTheOneOnScreen() async {
        let provider = GoDeeperQuestionProvider(generator: nil, store: memoryStore(), isModelAvailable: { false })
        let first = await provider.firstQuestion(text: lunch, mood: .happy)
        let next = provider.nextQuestion(text: lunch, mood: .happy, excluding: first)
        #expect(first != nil)
        #expect(next != nil)
        #expect(next != first)
    }

    // MARK: Titles

    @Test func titlesAreGeneratedOnceAndKeyedByEdit() async {
        let generator = MockTitleGenerator(reply: "Lunch with Maya by the lake")
        let titles = EntryTitleStore(generator: generator, store: memoryStore(), isModelAvailable: { true })
        let id = UUID()
        let edited = Date(timeIntervalSinceReferenceDate: 800_000_000)

        titles.requestTitle(entryID: id, updatedAt: edited, text: lunch, mood: .happy)
        await titles.waitUntilIdle()
        titles.requestTitle(entryID: id, updatedAt: edited, text: lunch, mood: .happy)
        await titles.waitUntilIdle()

        #expect(titles.title(entryID: id, updatedAt: edited, text: lunch) == "Lunch with Maya by the lake")
        #expect(generator.calls == 1)
        // A later edit has no title until it's asked for again.
        #expect(titles.title(entryID: id, updatedAt: edited.addingTimeInterval(60), text: lunch) == nil)
    }

    @Test func titlesFallBackToNoTitle() async {
        let invalid = MockTitleGenerator(reply: "A Lovely Lunch With Priya")
        let titles = EntryTitleStore(generator: invalid, store: memoryStore(), isModelAvailable: { true })
        let id = UUID()
        titles.requestTitle(entryID: id, updatedAt: nil, text: lunch, mood: .happy)
        await titles.waitUntilIdle()
        #expect(titles.title(entryID: id, updatedAt: nil, text: lunch) == nil)

        let unavailable = MockTitleGenerator(reply: "Lunch with Maya")
        let offTitles = EntryTitleStore(generator: unavailable, store: memoryStore(), isModelAvailable: { false })
        offTitles.requestTitle(entryID: id, updatedAt: nil, text: lunch, mood: .happy)
        await offTitles.waitUntilIdle()
        #expect(offTitles.title(entryID: id, updatedAt: nil, text: lunch) == nil)
        #expect(unavailable.calls == 0)
    }

    @Test func highRiskAndShortEntriesNeverReachTheTitleModel() async {
        let generator = MockTitleGenerator(reply: "Nights after the review")
        let titles = EntryTitleStore(generator: generator, store: memoryStore(), isModelAvailable: { true })

        titles.requestTitle(entryID: UUID(), updatedAt: nil, text: risky, mood: .sad)
        titles.requestTitle(entryID: UUID(), updatedAt: nil, text: "Lunch with Maya.", mood: .happy)
        await titles.waitUntilIdle()

        #expect(generator.calls == 0)
    }

    // MARK: Weekly Reflection

    @Test func weeklyProseReplacesOnlyTheCoverLineAndSummary() async throws {
        let (report, entries) = weeklyReport(texts: Self.calmWeek)
        let facts = try #require(WeeklyReflectionNarrationFacts(report: report, entries: entries))
        let theme = try #require(facts.themes.first)
        let narrator = MockNarrator(reply: WeeklyReflectionNarration(
            heroSentence: "Your week centered on \(theme.name.lowercased()).",
            summary: "You wrote \(facts.entryCount) entries on \(facts.entryDays) days, about \(facts.wordCount) words."
        ))

        let narrated = await WeeklyReflectionNarrator.narrated(report, entries: entries, narrator: narrator, isModelAvailable: true)

        #expect(narrator.calls == 1)
        #expect(narrated.heroSentence == "Your week centered on \(theme.name.lowercased()).")
        #expect(narrated.summary.hasPrefix("You wrote \(facts.entryCount) entries"))
        #expect(narrated.themes == report.themes)
        #expect(narrated.wins == report.wins)
        #expect(narrated.frictions == report.frictions)
        #expect(narrated.questions == report.questions)
        #expect(WeeklyReflectionGenerationService.validate(narrated))
    }

    @Test func weeklyProseFallsBackOnInventedFactsOrFailures() async throws {
        let (report, entries) = weeklyReport(texts: Self.calmWeek)
        let facts = try #require(WeeklyReflectionNarrationFacts(report: report, entries: entries))
        let bad: [WeeklyReflectionNarration] = [
            .init(heroSentence: "A full week of writing.", summary: "You wrote \(facts.entryCount + 7) entries this week."),
            .init(heroSentence: "A week with Arjun at the center.", summary: "You wrote \(facts.entryCount) entries this week."),
            .init(heroSentence: "What a journey this week was.", summary: "You wrote \(facts.entryCount) entries this week."),
            .init(heroSentence: "A week of writing.", summary: "Your symptoms eased as the week went on."),
            .init(heroSentence: "Did the week feel long?", summary: "You wrote \(facts.entryCount) entries this week."),
            .init(heroSentence: "I see a full week.", summary: "I counted \(facts.entryCount) entries this week."),
        ]
        for narration in bad {
            let narrated = await WeeklyReflectionNarrator.narrated(report, entries: entries, narrator: MockNarrator(reply: narration), isModelAvailable: true)
            #expect(narrated == report, "\(narration)")
        }

        let throwing = await WeeklyReflectionNarrator.narrated(report, entries: entries, narrator: MockNarrator(reply: nil, throws: true), isModelAvailable: true)
        #expect(throwing == report)

        let unavailable = MockNarrator(reply: .init(heroSentence: "A full week of writing.", summary: "You wrote \(facts.entryCount) entries."))
        let off = await WeeklyReflectionNarrator.narrated(report, entries: entries, narrator: unavailable, isModelAvailable: false)
        #expect(off == report)
        #expect(unavailable.calls == 0)
    }

    @Test func weeklyProseSkipsTheModelForAnyHeavyWeek() async {
        let narrator = MockNarrator(reply: .init(heroSentence: "A full week of writing.", summary: "You wrote 3 entries."))
        for heavyText in [heavy, risky] {
            let (report, entries) = weeklyReport(texts: Array(Self.calmWeek.dropLast()) + [heavyText + " " + Self.filler + " " + Self.filler])
            #expect(report.safetyLevel != .none)
            #expect(WeeklyReflectionNarrationFacts(report: report, entries: entries) == nil)
            let narrated = await WeeklyReflectionNarrator.narrated(report, entries: entries, narrator: narrator, isModelAvailable: true)
            #expect(narrated == report)
        }
        #expect(narrator.calls == 0)
    }

    @Test func weeklyFactsCarryNoEntryText() throws {
        let (report, entries) = weeklyReport(texts: Self.calmWeek)
        let facts = try #require(WeeklyReflectionNarrationFacts(report: report, entries: entries))
        for entry in entries {
            #expect(!facts.promptBlock.contains(entry.text.prefix(40)))
        }
    }

    // MARK: Entry insights

    @Test func entryInsightsAskNothingAboutHeavyEntries() {
        let normal = EntryInsightAnalyzer.analyze(text: lunch, responseMode: .normal)
        let gentle = EntryInsightAnalyzer.analyze(text: heavy, responseMode: .gentle)
        #expect(normal.fridayLine.contains("?"))
        #expect(!gentle.fridayLine.contains("?"))
        #expect(gentle.dominantEmotion == .fear)
    }

    @Test func entryInsightsNameRecurringTopicsOnce() {
        // Topics come from the part-of-speech model, which some simulators lack.
        guard !EntityExtractor.nouns(in: "The project deadline moved again.").isEmpty else { return }
        let insight = EntryInsightAnalyzer.analyze(text: "The project deadline moved again. The project review is Friday.", recurringTopic: { topic in
            topic.lowercased() == "project" ? "Project" : nil
        })
        #expect(insight.fridayLine.hasSuffix("Project comes up a lot for you."))
        #expect(insight.intent == .journaling || insight.intent == .planning)
    }

    // MARK: Helpers

    private func memoryStore() -> FridayGeneratedTextStore {
        FridayGeneratedTextStore(fileName: nil, capacity: 50)
    }

    static let filler = "We walked to the market after work, cooked dinner together, and talked about the garden plans for the weekend and the books we want to read next month."
    static let calmWeek = [
        "Lunch with Maya by the lake. The garden plans came together and the market was busy. " + filler + " " + filler,
        "Cooked dinner and read in the garden. The garden needs new soil before spring. " + filler + " " + filler,
        "Maya came over to look at the garden plans and we sketched the beds together. " + filler + " " + filler,
    ]

    private func weeklyReport(texts: [String]) -> (WeeklyReflectionReport, [WeeklyReflectionEntrySnapshot]) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let wednesday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 12))!
        let period = WeeklyReflectionEligibilityService.period(containing: wednesday)
        let entries = texts.enumerated().map { index, text in
            WeeklyReflectionEntrySnapshot(
                id: UUID(),
                date: period.start.addingTimeInterval(Double(index) * 86_400 + 36_000),
                updatedAt: period.start.addingTimeInterval(Double(index) * 86_400 + 36_000),
                mood: Mood.calm.rawValue,
                text: text,
                sourceType: .text
            )
        }
        let report = WeeklyReflectionGenerationService.generate(period: period, entries: entries, now: wednesday)
        return (report, entries)
    }
}

// MARK: - Mocks

final class MockQuestionGenerator: EntryQuestionGenerating, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    let reply: String?
    let shouldThrow: Bool

    init(reply: String?, throws shouldThrow: Bool = false) {
        self.reply = reply
        self.shouldThrow = shouldThrow
    }

    var calls: Int { lock.withLock { count } }

    func question(for context: EntryGenerationContext) async throws -> String? {
        lock.withLock { count += 1 }
        if shouldThrow { throw MockModelError.failed }
        return reply
    }
}

final class MockTitleGenerator: EntryTitleGenerating, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    let reply: String?

    init(reply: String?) { self.reply = reply }

    var calls: Int { lock.withLock { count } }

    func title(for context: EntryGenerationContext) async throws -> String? {
        lock.withLock { count += 1 }
        return reply
    }
}

final class MockNarrator: WeeklyReflectionNarrating, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    let reply: WeeklyReflectionNarration?
    let shouldThrow: Bool

    init(reply: WeeklyReflectionNarration?, throws shouldThrow: Bool = false) {
        self.reply = reply
        self.shouldThrow = shouldThrow
    }

    var calls: Int { lock.withLock { count } }

    func narrate(_ facts: WeeklyReflectionNarrationFacts) async throws -> WeeklyReflectionNarration? {
        lock.withLock { count += 1 }
        if shouldThrow { throw MockModelError.failed }
        return reply
    }
}

enum MockModelError: Error {
    case failed
}
