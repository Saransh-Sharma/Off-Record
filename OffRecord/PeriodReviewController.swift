//
//  PeriodReviewController.swift
//  OffRecord
//
//  Keeps Month in Review and Year in Review up to date. Reviews are stored
//  apart from weekly reports (their own AIState row), regenerate when an
//  entry in their period changes, and build off the main actor.
//

import CoreData
import Foundation
import os.log

private let periodReviewLogger = Logger(subsystem: "com.singularity.offrecord", category: "PeriodReview")

struct PeriodReviewRepository {
    static let stateType = "period_reviews"
    let context: NSManagedObjectContext

    struct Payload: Codable {
        var version: Int
        var reviews: [PeriodReview]
    }

    init(context: NSManagedObjectContext = PersistenceController.shared.container.viewContext) {
        self.context = context
    }

    func load() -> [PeriodReview] {
        let request = NSFetchRequest<AIState>(entityName: "AIState")
        request.predicate = NSPredicate(format: "type == %@", Self.stateType)
        request.fetchLimit = 1
        guard let state = try? context.fetch(request).first,
              let data = state.payload,
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.version == 1 else {
            return []
        }
        return payload.reviews
    }

    func save(_ reviews: [PeriodReview]) throws {
        let data = try JSONEncoder().encode(Payload(version: 1, reviews: reviews))
        let request = NSFetchRequest<AIState>(entityName: "AIState")
        request.predicate = NSPredicate(format: "type == %@", Self.stateType)
        request.fetchLimit = 1
        let existing = try context.fetch(request).first
        let state = existing ?? AIState(context: context)
        if existing == nil {
            state.id = UUID()
            state.type = Self.stateType
        }
        state.payload = data
        state.updatedAt = Date()
        try context.save()
    }
}

/// Everything a review needs from the journal, read on the main actor once.
struct PeriodReviewJournal: Sendable {
    var reflectionEntries: [WeeklyReflectionEntrySnapshot]
    var statEntries: [PeriodReviewStatEntry]
    var people: [PeriodReviewVocabularyItem]
    var topics: [PeriodReviewVocabularyItem]
    var forgottenLabels: Set<String>
    var citationCounts: [UUID: Int]

    static let empty = PeriodReviewJournal(reflectionEntries: [], statEntries: [], people: [], topics: [], forgottenLabels: [], citationCounts: [:])

    @MainActor
    init(entries: [DiaryEntry], weeklyReports: [WeeklyReflectionReport]? = nil) {
        let started = entries.filter(\.isStartedEntry)
        reflectionEntries = started.compactMap(WeeklyReflectionEntrySnapshot.init(entry:))
        statEntries = started.compactMap { entry in
            guard let id = entry.id else { return nil }
            let date = entry.date ?? entry.createdAt ?? Date()
            let snapshot = JournalEntrySnapshot(entry: entry)
            return PeriodReviewStatEntry(
                id: id,
                date: date,
                updatedAt: entry.updatedAt ?? date,
                wordCount: snapshot.wordCount,
                duration: snapshot.duration,
                mood: snapshot.mood,
                isStarred: snapshot.isStarred,
                photoCount: snapshot.photoCount
            )
        }

        let preferences = FridayMemoryPreferences.shared
        let graph = FridayAssistantEngine.shared.knowledgeGraph
        func vocabulary(_ type: PersonalKnowledgeGraph.KnowledgeNode.NodeType, limit: Int) -> [PeriodReviewVocabularyItem] {
            graph.nodes.values
                .filter { $0.type == type && !preferences.isForgotten($0) }
                .sorted { $0.importance > $1.importance }
                .prefix(limit)
                .map { PeriodReviewVocabularyItem(nodeID: $0.id, matchLabel: $0.label, displayLabel: preferences.displayName(for: $0)) }
        }
        people = vocabulary(.person, limit: 40)
        topics = vocabulary(.topic, limit: 60)
        forgottenLabels = Set(graph.nodes.values.filter { preferences.isForgotten($0) }.map { $0.label.lowercased() })

        var citations: [UUID: Int] = [:]
        for report in weeklyReports ?? WeeklyReflectionController.shared.visibleReports {
            for ref in report.themes.flatMap(\.evidenceRefs) {
                citations[ref.entryId, default: 0] += 1
            }
        }
        citationCounts = citations
    }

    init(
        reflectionEntries: [WeeklyReflectionEntrySnapshot],
        statEntries: [PeriodReviewStatEntry],
        people: [PeriodReviewVocabularyItem],
        topics: [PeriodReviewVocabularyItem],
        forgottenLabels: Set<String>,
        citationCounts: [UUID: Int]
    ) {
        self.reflectionEntries = reflectionEntries
        self.statEntries = statEntries
        self.people = people
        self.topics = topics
        self.forgottenLabels = forgottenLabels
        self.citationCounts = citationCounts
    }

    func input(kind: ReflectionPeriodKind, period: WeeklyReflectionPeriod, previous: PeriodReview?, now: Date, calendar: Calendar) -> PeriodReviewInput {
        PeriodReviewInput(
            kind: kind,
            period: period,
            reflectionEntries: reflectionEntries.filter { period.contains($0.date) },
            statEntries: statEntries.filter { period.contains($0.date) },
            people: people,
            topics: topics,
            forgottenLabels: forgottenLabels,
            citationCounts: citationCounts,
            previous: previous,
            now: now,
            calendar: calendar
        )
    }

    func signature(for period: WeeklyReflectionPeriod) -> String {
        PeriodReviewGenerator.inputSignature(
            entries: reflectionEntries.filter { period.contains($0.date) }.sorted { $0.date < $1.date },
            stats: statEntries.filter { period.contains($0.date) }
        )
    }

    func hasEntries(in period: WeeklyReflectionPeriod) -> Bool {
        statEntries.contains { period.contains($0.date) }
    }

    /// Years that have at least one entry, newest first.
    func years(calendar: Calendar) -> [Int] {
        Set(statEntries.map { calendar.component(.year, from: $0.date) }).sorted(by: >)
    }
}

@MainActor
final class PeriodReviewController: ObservableObject {
    static let shared = PeriodReviewController()

    /// Completed months kept up to date, newest first.
    static let monthHistoryCount = 12

    @Published private(set) var reviews: [PeriodReview]
    @Published private(set) var isRefreshing = false

    private let repository: PeriodReviewRepository
    private var refreshGeneration = 0

    private convenience init() {
        self.init(repository: PeriodReviewRepository())
    }

    init(repository: PeriodReviewRepository) {
        self.repository = repository
        self.reviews = repository.load()
    }

    var monthReviews: [PeriodReview] {
        reviews.filter { $0.kind == .month }.sorted { $0.report.periodStart > $1.report.periodStart }
    }

    func review(kind: ReflectionPeriodKind, key: String) -> PeriodReview? {
        reviews.first { $0.kind == kind && $0.periodKey == key }
    }

    func review(id: UUID) -> PeriodReview? {
        reviews.first { $0.id == id }
    }

    /// Years whose review can open now: past years with entries, and this year from December 1.
    func availableYears(journal: PeriodReviewJournal, now: Date = Date(), calendar: Calendar = .current) -> [Int] {
        journal.years(calendar: calendar).filter {
            ReflectionPeriodCalendar.isYearInReviewAvailable(year: $0, now: now, hasEntries: true, calendar: calendar)
        }
    }

    /// Brings the last 12 completed months up to date. Months without entries get no review.
    func refreshMonths(journal: PeriodReviewJournal, now: Date = Date(), calendar: Calendar = .current) async {
        let periods = ReflectionPeriodCalendar.completedPeriods(.month, before: now, count: Self.monthHistoryCount, calendar: calendar)
        var inputs: [PeriodReviewInput] = []
        for period in periods where journal.hasEntries(in: period) {
            let key = ReflectionPeriodCalendar.key(for: period, kind: .month, calendar: calendar)
            let existing = review(kind: .month, key: key)
            if let existing, existing.report.status != .failed, existing.report.inputSignature == journal.signature(for: period) {
                continue
            }
            inputs.append(journal.input(kind: .month, period: period, previous: existing, now: now, calendar: calendar))
        }
        guard !inputs.isEmpty else { return }
        await build(inputs)
    }

    /// The review for `year`, built if it's missing or out of date. Nil when the year isn't available yet.
    func yearReview(_ year: Int, journal: PeriodReviewJournal, now: Date = Date(), calendar: Calendar = .current) async -> PeriodReview? {
        guard ReflectionPeriodCalendar.isYearInReviewAvailable(year: year, now: now, hasEntries: !journal.years(calendar: calendar).filter({ $0 == year }).isEmpty, calendar: calendar),
              let period = ReflectionPeriodCalendar.year(year, calendar: calendar) else { return nil }
        let key = ReflectionPeriodCalendar.key(for: period, kind: .year, calendar: calendar)
        let existing = review(kind: .year, key: key)
        if let existing, existing.report.status != .failed, existing.report.inputSignature == journal.signature(for: period) {
            return existing
        }
        await build([journal.input(kind: .year, period: period, previous: existing, now: now, calendar: calendar)])
        return review(kind: .year, key: key)
    }

    /// The review for a month, built on demand (for links to a month outside the kept history).
    func monthReview(year: Int, month: Int, journal: PeriodReviewJournal, now: Date = Date(), calendar: Calendar = .current) async -> PeriodReview? {
        guard let period = ReflectionPeriodCalendar.month(year: year, month: month, calendar: calendar),
              period.end < now, journal.hasEntries(in: period) else { return nil }
        let key = ReflectionPeriodCalendar.key(for: period, kind: .month, calendar: calendar)
        let existing = review(kind: .month, key: key)
        if let existing, existing.report.status != .failed, existing.report.inputSignature == journal.signature(for: period) {
            return existing
        }
        await build([journal.input(kind: .month, period: period, previous: existing, now: now, calendar: calendar)])
        return review(kind: .month, key: key)
    }

    func saveTakeaway(_ text: String, for review: PeriodReview) {
        guard let index = reviews.firstIndex(where: { $0.id == review.id }) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        reviews[index].report.savedTakeaway = trimmed.isEmpty ? nil : trimmed
        persist()
    }

    private func build(_ inputs: [PeriodReviewInput]) async {
        refreshGeneration += 1
        let generation = refreshGeneration
        isRefreshing = true
        let built = await Task.detached(priority: .utility) {
            inputs.map(PeriodReviewGenerator.generate)
        }.value
        defer { if generation == refreshGeneration { isRefreshing = false } }
        for review in built {
            reviews.removeAll { $0.kind == review.kind && $0.periodKey == review.periodKey }
            reviews.append(review)
        }
        persist()
    }

    private func persist() {
        do {
            try repository.save(reviews)
        } catch {
            periodReviewLogger.error("Failed to save reviews: \(error.localizedDescription, privacy: .public)")
        }
    }

    #if DEBUG
    func resetForUITesting() {
        reviews = []
        persist()
    }
    #endif
}
