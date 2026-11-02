import CoreData
import Foundation
import JournalFoundation
import Testing
@testable import OffRecord

/// Month in Review and Year in Review: eligibility, safety, people and topics, stored format, and sharing.
struct PeriodReviewTests {

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 19) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private struct Seed {
        var day: Int
        var text: String
        var mood: Mood = .calm
        var starred = false
        var seconds: Double = 0
    }

    private func makeInput(
        _ seeds: [Seed],
        kind: ReflectionPeriodKind = .month,
        year: Int = 2026,
        month: Int = 9,
        people: [PeriodReviewVocabularyItem] = [],
        topics: [PeriodReviewVocabularyItem] = [],
        forgotten: Set<String> = [],
        citations: [UUID: Int] = [:]
    ) -> (PeriodReviewInput, [UUID]) {
        let period = kind == .year
            ? ReflectionPeriodCalendar.year(year, calendar: calendar)!
            : ReflectionPeriodCalendar.month(year: year, month: month, calendar: calendar)!
        var ids: [UUID] = []
        var reflection: [WeeklyReflectionEntrySnapshot] = []
        var stats: [PeriodReviewStatEntry] = []
        for seed in seeds {
            let id = UUID()
            ids.append(id)
            // For a year, spread entries one per month starting in January.
            let when = kind == .year ? date(year, min(12, seed.day), 10) : date(year, month, seed.day)
            reflection.append(WeeklyReflectionEntrySnapshot(id: id, date: when, updatedAt: when, mood: seed.mood.rawValue, text: seed.text, sourceType: .text))
            stats.append(PeriodReviewStatEntry(
                id: id, date: when, updatedAt: when,
                wordCount: seed.text.split(whereSeparator: \.isWhitespace).count,
                duration: seed.seconds, mood: seed.mood, isStarred: seed.starred, photoCount: 0
            ))
        }
        let input = PeriodReviewInput(
            kind: kind, period: period, reflectionEntries: reflection, statEntries: stats,
            people: people, topics: topics, forgottenLabels: forgotten, citationCounts: citations,
            previous: nil, now: date(2026, 10, 1, 9), calendar: calendar
        )
        return (input, ids)
    }

    /// Eight entries of about 30 words each: a full month (8 entries, over 200 words).
    private let gardenDays: [Seed] = [
        Seed(day: 2, text: "Spent the morning in the garden with Maya. The tomatoes are finally red and the basil is tall. We sat on the bench afterward and planned the beds for next spring.", mood: .happy, starred: true, seconds: 120),
        Seed(day: 5, text: "Work was busy, but the garden after dinner helped. Maya brought seedlings from her balcony, and we planted them in the corner bed before it got dark outside.", mood: .calm),
        Seed(day: 9, text: "Quiet day. Read on the porch and watered the garden before the rain came in from the west. Made soup and went to bed early with the window open.", mood: .calm, seconds: 300),
        Seed(day: 14, text: "Long week at work. The project deadline moved again and the team meeting ran late into the evening, so I walked home the long way to clear my head.", mood: .tired),
        Seed(day: 18, text: "Planted garlic in the garden for next year. Maya says it will be ready by July if the winter stays mild. The soil was soft after the rain this week.", mood: .grateful),
        Seed(day: 22, text: "Walked by the river with Sam after work. The garden needs weeding this weekend before the leaves start to fall, and the gate needs a new hinge too.", mood: .happy),
        Seed(day: 26, text: "Harvested the last tomatoes from the garden and made sauce with Maya for the freezer. The kitchen smelled like summer all evening, and we ate on the steps.", mood: .happy, starred: true),
        Seed(day: 29, text: "Cleaned up the garden beds and wrote down what to plant in spring with Maya over a long cup of tea. It felt good to close out the season properly.", mood: .calm)
    ]

    // MARK: Eligibility

    @Test func monthWithTooFewEntriesSaysTheRealThreshold() {
        let (input, _) = makeInput([Seed(day: 3, text: "Short note about the weather and a walk in the park today.")])
        let review = PeriodReviewGenerator.generate(input)

        #expect(review.report.status == .insufficientData)
        #expect(review.report.summary.contains("\(ReflectionPeriodKind.month.thresholds.minimumEntryCount)"))
        #expect(review.report.themes.isEmpty)
        #expect(review.stats.highlights.isEmpty)
        #expect(review.periodKey == "2026-09")
    }

    @Test func fullMonthHasThemesPeopleHighlightsAndStats() {
        let maya = PeriodReviewVocabularyItem(nodeID: "maya", matchLabel: "Maya", displayLabel: "Maya")
        let (input, ids) = makeInput(gardenDays, people: [maya], citations: [:])
        let review = PeriodReviewGenerator.generate(input)

        #expect(review.report.status == .ready)
        #expect(review.report.eligibility == .full)
        #expect(review.stats.entryCount == 8)
        #expect(review.stats.activeDays == 8)
        #expect(review.stats.recordedMinutes == 7)
        #expect(review.stats.starredCount == 2)
        #expect(review.stats.topPeople.first?.label == "Maya")
        #expect(review.stats.topPeople.first?.entryCount == 5)
        #expect(review.stats.topTopics.map { $0.label.lowercased() }.contains("garden"))
        #expect(!review.report.themes.isEmpty)
        // Starred entries lead the highlights.
        #expect(review.stats.highlights.first.map { [ids[0], ids[6]].contains($0.entryId) } == true)
        #expect(review.stats.moodBuckets.count >= 4)
        #expect(!review.touchesHighRiskContent)
        #expect(!review.report.questions.isEmpty)
        #expect(PeriodReviewGenerator.isValid(review, highRiskEntryIds: []))
    }

    @Test func generationIsDeterministic() {
        let (input, _) = makeInput(gardenDays)
        let first = PeriodReviewGenerator.generate(input)
        let second = PeriodReviewGenerator.generate(input)

        #expect(first.report.heroSentence == second.report.heroSentence)
        #expect(first.report.summary == second.report.summary)
        #expect(first.stats == second.stats)
        #expect(first.report.inputSignature == second.report.inputSignature)
    }

    // MARK: Safety

    @Test func highRiskEntriesAreNeverAnalyzedOrQuoted() {
        var seeds = gardenDays
        seeds.append(Seed(day: 30, text: "I keep thinking about ending my life and Maya doesn't know. The garden doesn't help anymore.", mood: .sad, starred: true))
        let maya = PeriodReviewVocabularyItem(nodeID: "maya", matchLabel: "Maya", displayLabel: "Maya")
        let (input, ids) = makeInput(seeds, people: [maya])
        let riskyID = ids.last!
        let review = PeriodReviewGenerator.generate(input)

        #expect(review.report.safetyLevel == .highRiskExcluded)
        #expect(review.touchesHighRiskContent)
        #expect(review.stats.excludedEntryCount == 1)
        #expect(!review.stats.highlights.contains { $0.entryId == riskyID })
        #expect(!review.report.themes.flatMap(\.evidenceRefs).contains { $0.entryId == riskyID })
        #expect(review.stats.topPeople.first?.entryCount == 5) // the risky entry's mention isn't counted
        let generatedText = ([review.report.heroSentence, review.report.summary] + review.report.wins + review.report.frictions
            + review.report.themes.flatMap { $0.evidenceRefs.compactMap(\.quote) } + review.stats.highlights.map(\.snippet)).joined(separator: " ")
        #expect(!generatedText.localizedCaseInsensitiveContains("ending my life"))
        #expect(review.report.questions.isEmpty)
        // Counts still include every entry.
        #expect(review.stats.entryCount == 9)
        #expect(PeriodReviewGenerator.isValid(review, highRiskEntryIds: [riskyID]))
    }

    @Test func onlyHighRiskEntriesGiveAShortSupportiveReview() {
        let text = "Some days I want to die. I don't want to be alive and nothing helps at all lately. Work keeps piling up, I can't sleep, and the evenings are the hardest part of every single week."
        let seeds = (1...6).map { Seed(day: $0 * 3, text: text, mood: .sad) }
        let (input, _) = makeInput(seeds)
        let review = PeriodReviewGenerator.generate(input)

        #expect(review.report.status == .ready)
        #expect(review.report.safetyLevel == .highRiskExcluded)
        #expect(review.report.themes.isEmpty)
        #expect(review.stats.highlights.isEmpty)
        #expect(review.stats.topTopics.isEmpty)
        #expect(review.report.questions.isEmpty)
        #expect(review.touchesHighRiskContent)
    }

    @Test func distressKeepsTheReviewButAsksNothing() {
        var seeds = gardenDays
        seeds[3] = Seed(day: 14, text: "Completely overwhelmed by work this week. The project deadline moved again and the team meeting ran late into the evening, so I walked home the long way.", mood: .anxious)
        let (input, _) = makeInput(seeds)
        let review = PeriodReviewGenerator.generate(input)

        #expect(review.report.safetyLevel == .mildDistress)
        #expect(review.report.status == .ready)
        #expect(review.report.questions.isEmpty)
        #expect(!review.touchesHighRiskContent)
    }

    @Test func entriesExcludedFromAIStillCountButAreNotRead() {
        // Entries excluded from AI arrive with empty text but keep their word count (see A1's snapshot gate).
        var (input, ids) = makeInput(gardenDays)
        let hidden = input.reflectionEntries[1]
        input.reflectionEntries[1] = WeeklyReflectionEntrySnapshot(id: hidden.id, date: hidden.date, updatedAt: hidden.updatedAt, mood: hidden.mood, text: "", sourceType: .text)
        let review = PeriodReviewGenerator.generate(input)

        #expect(review.stats.entryCount == 8)
        #expect(!review.stats.highlights.contains { $0.entryId == ids[1] })
        #expect(!review.report.themes.flatMap(\.evidenceRefs).contains { $0.entryId == ids[1] })
    }

    // MARK: People and topics

    @Test func forgottenPeopleAreLeftOutAndRenamesAreUsed() {
        let maya = PeriodReviewVocabularyItem(nodeID: "maya", matchLabel: "Maya", displayLabel: "My sister")
        let sam = PeriodReviewVocabularyItem(nodeID: "sam", matchLabel: "Sam", displayLabel: "Sam")
        let (input, _) = makeInput(gardenDays, people: [maya, sam], forgotten: ["sam"])
        let review = PeriodReviewGenerator.generate(input)

        #expect(review.stats.topPeople.map(\.label) == ["My sister"])
        #expect(review.stats.topPeople.first?.nodeID == "maya")
    }

    @Test func peopleFallBackToNamesInTheText() {
        let (input, _) = makeInput(gardenDays)
        let review = PeriodReviewGenerator.generate(input)
        // NaturalLanguage name tagging varies by OS build; when it finds names, they come from the text.
        for person in review.stats.topPeople {
            #expect(gardenDays.contains { $0.text.contains(person.label) })
        }
    }

    @Test func citedEntriesRankAsEntriesThatMattered() {
        let (base, ids) = makeInput(gardenDays)
        var input = base
        input.citationCounts = [ids[3]: 3]
        let review = PeriodReviewGenerator.generate(input)

        #expect(review.stats.highlights.first?.entryId == ids[3])
        #expect(review.stats.highlights.first?.reasons.contains(.cited) == true)
    }

    // MARK: Year

    @Test func yearReviewBucketsMoodByMonthAndKeepsPixels() {
        let seeds = (1...12).flatMap { month in
            [Seed(day: month, text: "Notes about the garden, reading on the porch, and long walks with Maya near the lake. The tomatoes and the basil both did well, and the evenings were quiet and slow.", mood: month < 7 ? .tired : .happy)]
        } + (1...12).map { Seed(day: $0, text: "Another entry about work, the garden, and the lake path. The team meeting ran long again, so I walked home the slow way and cooked dinner with the radio on.", mood: .calm) }
        let (input, _) = makeInput(seeds, kind: .year, year: 2025)
        let review = PeriodReviewGenerator.generate(input)

        #expect(review.kind == .year)
        #expect(review.periodKey == "2025")
        #expect(review.stats.moodBuckets.count == 12)
        #expect(review.stats.moodBuckets.allSatisfy { $0.entryCount == 2 })
        #expect(review.stats.moodDays.count == 12)
        #expect(review.report.status == .ready)
        #expect(review.stats.highlights.count <= 5)
    }

    // MARK: Storage

    @Test func weeklyPayloadDecodesUnchanged() throws {
        let id = UUID()
        let json = """
        {"version":1,"settings":{"isEnabled":true,"reminderWeekday":1,"reminderHour":19,"reminderMinute":0,"showHomeCard":true,"sendNotification":true},
         "reports":[{"id":"\(id.uuidString)","periodStart":780000000,"periodEnd":780604799,"generatedAt":780604799,"versionNumber":1,
           "processingMode":"local","status":"ready","eligibility":"full","includedEntryIds":[],"hiddenEntryIds":[],"unavailableEntryIds":[],
           "privateEntryCount":0,"inputSignature":"sig","heroSentence":"Hero.","summary":"Summary.","themes":[],"wins":[],"frictions":[],
           "questions":["Q?"],"safetyLevel":"none"}]}
        """
        let payload = try JSONDecoder().decode(WeeklyReflectionRepository.Payload.self, from: Data(json.utf8))
        #expect(payload.reports.first?.id == id)
        #expect(payload.reports.first?.questions == ["Q?"])
    }

    @MainActor
    @Test func reviewsPersistApartFromWeeklyReports() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let repository = PeriodReviewRepository(context: context)
        let (input, _) = makeInput(gardenDays)
        let review = PeriodReviewGenerator.generate(input)
        try repository.save([review])

        #expect(repository.load() == [review])
        #expect(WeeklyReflectionRepository(context: context).load().reports.isEmpty)
    }

    @MainActor
    @Test func controllerBuildsCompletedMonthsAndSkipsUnchangedOnes() async throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let controller = PeriodReviewController(repository: PeriodReviewRepository(context: context))
        let (input, _) = makeInput(gardenDays)
        let journal = PeriodReviewJournal(
            reflectionEntries: input.reflectionEntries, statEntries: input.statEntries,
            people: [], topics: [], forgottenLabels: [], citationCounts: [:]
        )

        await controller.refreshMonths(journal: journal, now: date(2026, 10, 1, 9), calendar: calendar)
        let first = try #require(controller.review(kind: .month, key: "2026-09"))
        #expect(controller.monthReviews.count == 1)

        await controller.refreshMonths(journal: journal, now: date(2026, 10, 2, 9), calendar: calendar)
        #expect(controller.review(kind: .month, key: "2026-09")?.id == first.id)

        // The current year opens only from December 1; 2026 has entries but it's October.
        #expect(controller.availableYears(journal: journal, now: date(2026, 10, 1), calendar: calendar).isEmpty)
        #expect(controller.availableYears(journal: journal, now: date(2026, 12, 1, 0), calendar: calendar) == [2026])
        #expect(await controller.yearReview(2026, journal: journal, now: date(2026, 10, 1), calendar: calendar) == nil)
        #expect(await controller.yearReview(2026, journal: journal, now: date(2026, 12, 2), calendar: calendar)?.periodKey == "2026")
    }

    // MARK: Sharing

    @Test func shareCardHidesNamesUnlessShown() {
        let content = YearInReviewShareContent(
            year: 2025, entryCount: 200, activeDays: 150, wordCount: 40_000, recordedMinutes: 90,
            people: ["Maya", "Sam"], topics: ["Garden", "Work"], moodDays: [], periodStart: date(2025, 1, 1)
        )
        let hidden = content.sharingVersion(includeNames: false).visibleLines.joined(separator: "\n")
        #expect(!hidden.contains("Maya"))
        #expect(!hidden.contains("Sam"))
        #expect(hidden.contains(ShareableInsightPrivacy.placeholder))
        #expect(hidden.contains("Garden"))

        let shown = content.sharingVersion(includeNames: true).visibleLines.joined(separator: "\n")
        #expect(shown.contains("Maya") && shown.contains("Sam"))
    }

    @Test func shareCardRedactsNamesThatSlipIntoTopics() {
        let content = YearInReviewShareContent(
            year: 2025, entryCount: 3, activeDays: 3, wordCount: 300, recordedMinutes: 0,
            people: ["Priya"], topics: ["Priya", "Running"], moodDays: [], periodStart: date(2025, 1, 1)
        )
        let lines = content.sharingVersion(includeNames: false).visibleLines.joined(separator: " ")
        #expect(!lines.contains("Priya"))
    }
}
