//
//  PeriodReviewGenerator.swift
//  OffRecord
//
//  Builds Month in Review and Year in Review from the same pieces as Weekly
//  Reflection: kind-aware eligibility, the safety filter, topic extraction,
//  and the shared report envelope. Deterministic: the same entries always
//  give the same review.
//
//  Safety: high-risk entries are counted but never analyzed or quoted. They
//  don't feed themes, people, topics, highlights, or the mood arc, and a
//  review that touches them shows Get Support. Mild or moderate distress
//  keeps the review but asks no questions.
//

import Foundation
import JournalFoundation
import NaturalLanguage

/// Plain numbers for one started entry. Every started entry counts here, as on the Insights Writing card.
struct PeriodReviewStatEntry: Hashable, Sendable {
    let id: UUID
    let date: Date
    let updatedAt: Date
    let wordCount: Int
    let duration: Double
    let mood: Mood
    let isStarred: Bool
    let photoCount: Int
}

/// A person or topic Friday knows about: the label to look for and the name to show.
struct PeriodReviewVocabularyItem: Hashable, Sendable {
    let nodeID: String
    let matchLabel: String
    let displayLabel: String
}

struct PeriodReviewInput: Sendable {
    var kind: ReflectionPeriodKind
    var period: WeeklyReflectionPeriod
    /// Entries as reflections may read them (`WeeklyReflectionEntrySnapshot(entry:)`, which applies AI exclusion).
    var reflectionEntries: [WeeklyReflectionEntrySnapshot]
    var statEntries: [PeriodReviewStatEntry]
    var people: [PeriodReviewVocabularyItem] = []
    var topics: [PeriodReviewVocabularyItem] = []
    /// Lowercased labels the person asked Friday to forget.
    var forgottenLabels: Set<String> = []
    /// How often weekly reflections cited each entry.
    var citationCounts: [UUID: Int] = [:]
    var previous: PeriodReview?
    var now: Date = Date()
    var calendar: Calendar = .current
}

enum PeriodReviewGenerator {
    /// Bump when the generated content changes shape, so stored reviews are rebuilt.
    static let generatorVersion = 1

    static func generate(_ input: PeriodReviewInput) -> PeriodReview {
        let calendar = input.calendar
        let period = input.period
        let key = ReflectionPeriodCalendar.key(for: period, kind: input.kind, calendar: calendar)
        let periodEntries = input.reflectionEntries
            .filter { period.contains($0.date) }
            .sorted { $0.date < $1.date }
        let statEntries = input.statEntries.filter { period.contains($0.date) }.sorted { $0.date < $1.date }

        let eligibility = WeeklyReflectionEligibilityEngine.evaluate(entries: periodEntries, in: period, kind: input.kind)
        let highRiskIDs = Set(periodEntries.filter(WeeklyReflectionSafetyFilter.isHighRisk).map(\.id))
        // Text analysis reads only entries that are safe and have text (entries excluded from AI arrive without text).
        let insightEntries = periodEntries.filter { !highRiskIDs.contains($0.id) && !$0.text.isEmpty }
        let safetyLevel = WeeklyReflectionSafetyFilter.safetyLevel(for: periodEntries)
        let words = PeriodWords(kind: input.kind, period: period, calendar: calendar)
        let signature = inputSignature(entries: periodEntries, stats: statEntries)

        var stats = baseStats(statEntries, kind: input.kind, period: period, calendar: calendar)
        stats.excludedEntryCount = highRiskIDs.count

        func review(
            status: WeeklyReflectionStatus,
            hero: String,
            summary: String,
            arc: WeeklyReflectionEmotionalArc? = nil,
            themes: [WeeklyReflectionTheme] = [],
            wins: [String] = [],
            frictions: [String] = [],
            questions: [String] = []
        ) -> PeriodReview {
            let report = WeeklyReflectionReport(
                id: UUID(),
                periodStart: period.start,
                periodEnd: period.end,
                generatedAt: input.now,
                versionNumber: (input.previous?.report.versionNumber ?? 0) + 1,
                processingMode: .local,
                status: status,
                eligibility: eligibility.kind,
                includedEntryIds: periodEntries.map(\.id),
                hiddenEntryIds: [],
                unavailableEntryIds: [],
                privateEntryCount: 0,
                inputSignature: signature,
                heroSentence: WeeklyReflectionSafetyFilter.sanitized(hero),
                summary: WeeklyReflectionSafetyFilter.sanitized(summary),
                emotionalArc: arc,
                themes: themes,
                wins: wins.map(WeeklyReflectionSafetyFilter.sanitized),
                frictions: frictions.map(WeeklyReflectionSafetyFilter.sanitized),
                questions: questions.map(WeeklyReflectionSafetyFilter.sanitized),
                savedTakeaway: input.previous?.report.savedTakeaway,
                safetyLevel: safetyLevel,
                userMarkedHelpful: input.previous?.report.userMarkedHelpful
            )
            let result = PeriodReview(kind: input.kind, periodKey: key, report: report, stats: stats)
            return isValid(result, highRiskEntryIds: highRiskIDs) ? result : failed(input, key: key, signature: signature, stats: stats)
        }

        if eligibility.kind == .empty {
            return review(status: .insufficientData, hero: words.emptyHero, summary: words.notEnough(eligibility))
        }

        if insightEntries.isEmpty {
            return review(
                status: .ready,
                hero: safetyLevel == .highRiskExcluded ? words.heavyHero : words.lightHero,
                summary: safetyLevel == .highRiskExcluded ? words.heavySummary : words.counts(stats),
                wins: [words.keptWriting]
            )
        }

        let isFull = eligibility.kind == .full
        stats.topPeople = topMentions(input.people, fallback: detectedPeople(in: insightEntries), in: insightEntries, forgotten: input.forgottenLabels, limit: 5)
        let personLabels = Set(stats.topPeople.map { $0.label.lowercased() })
        let fallbackTopics = WeeklyReflectionGenerationService.topTopics(in: insightEntries, limit: 8)
            .filter { !personLabels.contains($0.lowercased()) }
        stats.topTopics = topMentions(input.topics, fallback: fallbackTopics, in: insightEntries, forgotten: input.forgottenLabels.union(personLabels), limit: 5)
        stats.highlights = highlights(
            insightEntries,
            stats: statEntries,
            citations: input.citationCounts,
            mentions: stats.topPeople + stats.topTopics,
            limit: input.kind == .year ? 5 : 3
        )

        let topicLabels = stats.topTopics.map(\.label)
        let themes = makeThemes(topicLabels, entries: insightEntries, limit: isFull ? 4 : 2)
        let arc = makeArc(insightEntries, words: words)

        var summaryParts = [words.counts(stats)]
        if !topicLabels.isEmpty {
            summaryParts.append(String(localized: "You wrote most about \(Array(topicLabels.prefix(3)).formatted(.list(type: .and))).", comment: "Review summary; the argument is a list of topics"))
        }
        if let arc { summaryParts.append(arc.description) }
        if safetyLevel == .highRiskExcluded { summaryParts.append(words.heavyNote) }

        var wins = [String(AttributedString(localized: "You wrote on ^[\(stats.activeDays) day](inflect: true).").characters)]
        if insightEntries.contains(where: { $0.sentiment > 0.25 }) {
            wins.append(String(localized: "Some entries were upbeat or grateful."))
        }
        var frictions: [String] = []
        if safetyLevel == .highRiskExcluded {
            frictions.append(String(localized: "Some entries were heavier than usual."))
        } else if insightEntries.contains(where: { $0.sentiment < -0.2 }) {
            frictions.append(words.heavierParts)
        }
        if let first = topicLabels.first, (stats.topTopics.first?.entryCount ?? 0) > 1 {
            frictions.append(String(localized: "\(first) came up more than once."))
        }
        if frictions.isEmpty { frictions.append(words.nothingHard) }

        // Design.md "Gentle": with any distress in the period, ask nothing.
        var questions: [String] = []
        if safetyLevel == .none {
            if input.kind == .month, let topic = topicLabels.first {
                questions.append(String(localized: "What do you want to remember about \(topic.lowercased())?"))
            }
            questions.append(words.lookAhead)
        }

        let hero: String
        if safetyLevel == .highRiskExcluded {
            hero = words.heavyHero
        } else if !isFull {
            hero = words.lightHero
        } else if let topic = topicLabels.first {
            hero = words.mostlyAbout(topic.lowercased(), arc: arc)
        } else {
            hero = words.fewThings
        }

        return review(
            status: .ready,
            hero: hero,
            summary: summaryParts.joined(separator: " "),
            arc: arc,
            themes: themes,
            wins: Array(wins.prefix(isFull ? 3 : 1)),
            frictions: Array(frictions.prefix(isFull ? 3 : 1)),
            questions: Array(questions.prefix(isFull ? 2 : 1))
        )
    }

    /// Changes when an entry in the period is added, edited, or removed.
    static func inputSignature(entries: [WeeklyReflectionEntrySnapshot], stats: [PeriodReviewStatEntry]) -> String {
        let reflection = WeeklyReflectionGenerationService.inputSignature(for: entries)
        let statPart = stats
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSinceReferenceDate)" }
            .joined(separator: "|")
        return "v\(generatorVersion)#\(reflection)#stats:\(statPart)"
    }

    /// The weekly report checks, plus: highlights and theme evidence never point at a high-risk entry.
    static func isValid(_ review: PeriodReview, highRiskEntryIds: Set<UUID>) -> Bool {
        let report = review.report
        guard report.heroSentence.split(separator: " ").count <= 25,
              report.summary.split(separator: " ").count <= 120,
              report.questions.count <= 3,
              report.wins.count <= 3,
              report.frictions.count <= 3 else { return false }
        let included = Set(report.includedEntryIds)
        let refs = report.themes.flatMap(\.evidenceRefs)
        guard refs.allSatisfy({ included.contains($0.entryId) && !highRiskEntryIds.contains($0.entryId) }) else { return false }
        guard review.stats.highlights.allSatisfy({ !highRiskEntryIds.contains($0.entryId) }) else { return false }
        return WeeklyReflectionSafetyFilter.isValidOutput(report)
    }

    // MARK: - Stats

    static func baseStats(
        _ entries: [PeriodReviewStatEntry],
        kind: ReflectionPeriodKind,
        period: WeeklyReflectionPeriod,
        calendar: Calendar
    ) -> PeriodReviewStats {
        var moodByDay: [Date: (mood: Mood, updatedAt: Date)] = [:]
        for entry in entries {
            let day = calendar.startOfDay(for: entry.date)
            if let current = moodByDay[day], current.updatedAt > entry.updatedAt, current.mood != .none { continue }
            if entry.mood != .none || moodByDay[day] == nil {
                moodByDay[day] = (entry.mood, entry.updatedAt)
            }
        }
        let moodDays = moodByDay.keys.sorted().map { PeriodReviewMoodDay(day: $0, mood: moodByDay[$0]?.mood.rawValue ?? "") }

        return PeriodReviewStats(
            entryCount: entries.count,
            activeDays: moodByDay.count,
            wordCount: entries.reduce(0) { $0 + $1.wordCount },
            recordedSeconds: entries.reduce(0) { $0 + max(0, $1.duration) },
            photoCount: entries.reduce(0) { $0 + $1.photoCount },
            starredCount: entries.filter(\.isStarred).count,
            moodDays: moodDays,
            moodBuckets: moodBuckets(entries, kind: kind, period: period, calendar: calendar),
            topPeople: [],
            topTopics: [],
            highlights: [],
            excludedEntryCount: 0
        )
    }

    /// Weeks of a month, or months of a year, each with its most common mood and average valence.
    static func moodBuckets(
        _ entries: [PeriodReviewStatEntry],
        kind: ReflectionPeriodKind,
        period: WeeklyReflectionPeriod,
        calendar baseCalendar: Calendar
    ) -> [PeriodReviewMoodBucket] {
        let calendar = ReflectionPeriodCalendar.calendar(from: baseCalendar)
        var starts: [Date] = []
        switch kind {
        case .year:
            var cursor = period.start
            while cursor <= period.end {
                starts.append(cursor)
                guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
                cursor = next
            }
        case .month, .week:
            var cursor = period.start
            while cursor <= period.end {
                starts.append(cursor)
                let weekEnd = ReflectionPeriodCalendar.period(.week, containing: cursor, calendar: calendar).end
                cursor = weekEnd.addingTimeInterval(1)
            }
        }
        return starts.enumerated().map { index, start in
            let end = index + 1 < starts.count ? starts[index + 1] : period.end.addingTimeInterval(1)
            let slice = entries.filter { $0.date >= start && $0.date < end }
            let moods = slice.map(\.mood).filter { $0 != .none }
            let counts = Dictionary(grouping: moods, by: { $0 }).mapValues(\.count)
            let dominant = counts.sorted { $0.value == $1.value ? $0.key.rawValue < $1.key.rawValue : $0.value > $1.value }.first?.key
            let average = moods.isEmpty ? nil : moods.reduce(0) { $0 + $1.valence } / Double(moods.count)
            return PeriodReviewMoodBucket(start: start, dominantMood: dominant?.rawValue, averageValence: average, entryCount: slice.count)
        }
    }

    // MARK: - People, topics, highlights

    /// Known people or topics first (counted by entries that mention them), topped up from text signals.
    static func topMentions(
        _ vocabulary: [PeriodReviewVocabularyItem],
        fallback: [String],
        in entries: [WeeklyReflectionEntrySnapshot],
        forgotten: Set<String>,
        limit: Int
    ) -> [PeriodReviewMention] {
        var found: [PeriodReviewMention] = []
        var seen = Set<String>()
        for item in vocabulary {
            let key = item.matchLabel.lowercased()
            guard !forgotten.contains(key), !forgotten.contains(item.displayLabel.lowercased()), seen.insert(key).inserted else { continue }
            let count = entries.filter { textContains(item.matchLabel, in: $0.text) }.count
            if count > 0 { found.append(PeriodReviewMention(nodeID: item.nodeID, label: item.displayLabel, entryCount: count)) }
        }
        for label in fallback {
            let key = label.lowercased()
            guard !forgotten.contains(key), seen.insert(key).inserted else { continue }
            let count = entries.filter { textContains(label, in: $0.text) }.count
            if count > 0 {
                found.append(PeriodReviewMention(nodeID: nil, label: label.prefix(1).uppercased() + label.dropFirst(), entryCount: count))
            }
        }
        return Array(found
            .sorted { $0.entryCount == $1.entryCount ? $0.label < $1.label : $0.entryCount > $1.entryCount }
            .prefix(limit))
    }

    /// Personal names NaturalLanguage finds in the entries, most mentioned first.
    static func detectedPeople(in entries: [WeeklyReflectionEntrySnapshot]) -> [String] {
        var counts: [String: Int] = [:]
        for entry in entries {
            for name in Set(ShareableInsightPrivacy.detectedNames(in: [entry.text])) {
                counts[name, default: 0] += 1
            }
        }
        return counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.map(\.key)
    }

    /// Entries that mattered: starred (3 points), cited by weekly reflections (2 per citation),
    /// and mentions of the period's top people and topics (1 each, at most 2), so stars and
    /// citations lead. Ties go to the longer entry.
    static func highlights(
        _ entries: [WeeklyReflectionEntrySnapshot],
        stats: [PeriodReviewStatEntry],
        citations: [UUID: Int],
        mentions topItems: [PeriodReviewMention],
        limit: Int
    ) -> [PeriodReviewHighlight] {
        let starred = Set(stats.filter(\.isStarred).map(\.id))
        let labels = topItems.map(\.label)
        let scored: [(PeriodReviewHighlight, Int)] = entries.compactMap { entry in
            var reasons: [PeriodReviewHighlightReason] = []
            var score = 0
            if starred.contains(entry.id) { reasons.append(.starred); score += 3 }
            if let cited = citations[entry.id], cited > 0 { reasons.append(.cited); score += 2 * cited }
            let mentioned = labels.filter { textContains($0, in: entry.text) }.count
            if mentioned >= 2 { reasons.append(.mentions) }
            score += min(mentioned, 2)
            guard score >= 2 else { return nil }
            return (PeriodReviewHighlight(
                entryId: entry.id,
                date: entry.date,
                snippet: ProactiveReflectionAnalyzer.snippet(entry.text),
                reasons: reasons,
                score: score
            ), entry.wordCount)
        }
        return scored
            .sorted { lhs, rhs in
                if lhs.0.score != rhs.0.score { return lhs.0.score > rhs.0.score }
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return lhs.0.date < rhs.0.date
            }
            .prefix(limit)
            .map(\.0)
    }

    /// Whole-word, case-insensitive match.
    static func textContains(_ label: String, in text: String) -> Bool {
        guard !label.isEmpty else { return false }
        let pattern = "\\b" + NSRegularExpression.escapedPattern(for: label) + "\\b"
        return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    // MARK: - Themes and arc

    static func makeThemes(_ topics: [String], entries: [WeeklyReflectionEntrySnapshot], limit: Int) -> [WeeklyReflectionTheme] {
        topics.prefix(limit).compactMap { topic in
            let matches = entries.filter { textContains(topic, in: $0.text) }
            guard !matches.isEmpty else { return nil }
            let refs = matches.prefix(3).map { entry in
                WeeklyReflectionEvidenceRef(
                    id: UUID(),
                    entryId: entry.id,
                    entryDate: entry.date,
                    sourceType: entry.sourceType,
                    quote: ProactiveReflectionAnalyzer.snippet(entry.text),
                    reason: String(localized: "Mentions this.", comment: "Why an entry is cited as evidence for a weekly reflection theme")
                )
            }
            return WeeklyReflectionTheme(
                id: UUID(),
                title: topic,
                summary: String(AttributedString(localized: "Came up in ^[\(matches.count) entry](inflect: true).").characters),
                evidenceRefs: Array(refs)
            )
        }
    }

    static func makeArc(_ entries: [WeeklyReflectionEntrySnapshot], words: PeriodWords) -> WeeklyReflectionEmotionalArc? {
        guard entries.count >= 4 else { return nil }
        let half = entries.count / 2
        let first = entries.prefix(half).map(\.sentiment).reduce(0, +) / Double(half)
        let secondHalf = entries.suffix(entries.count - half)
        let second = secondHalf.map(\.sentiment).reduce(0, +) / Double(secondHalf.count)
        if second > first + 0.15 {
            return WeeklyReflectionEmotionalArc(label: PeriodWords.ArcLabel.lighter, description: words.arcLighter)
        } else if second < first - 0.15 {
            return WeeklyReflectionEmotionalArc(label: PeriodWords.ArcLabel.heavier, description: words.arcHeavier)
        }
        return WeeklyReflectionEmotionalArc(label: PeriodWords.ArcLabel.steady, description: words.arcSteady)
    }

    private static func failed(_ input: PeriodReviewInput, key: String, signature: String, stats: PeriodReviewStats) -> PeriodReview {
        var safeStats = stats
        safeStats.topPeople = []
        safeStats.topTopics = []
        safeStats.highlights = []
        let report = WeeklyReflectionReport(
            id: UUID(),
            periodStart: input.period.start,
            periodEnd: input.period.end,
            generatedAt: input.now,
            versionNumber: (input.previous?.report.versionNumber ?? 0) + 1,
            processingMode: .local,
            status: .failed,
            eligibility: .empty,
            includedEntryIds: [],
            hiddenEntryIds: [],
            unavailableEntryIds: [],
            privateEntryCount: 0,
            inputSignature: signature,
            heroSentence: String(localized: "I couldn’t put this review together."),
            summary: String(localized: "Your entries are fine. Try again in a bit."),
            emotionalArc: nil,
            themes: [],
            wins: [],
            frictions: [],
            questions: [],
            savedTakeaway: nil,
            safetyLevel: .none,
            userMarkedHelpful: nil
        )
        return PeriodReview(kind: input.kind, periodKey: key, report: report, stats: safeStats)
    }
}

/// The words that change between a month and a year review, in Friday's voice.
struct PeriodWords {
    /// Stored English identifiers, the same as Weekly Reflection's (shown via `localizedLabel`).
    enum ArcLabel {
        static let lighter = "Got Lighter"
        static let heavier = "Got Heavier"
        static let steady = "Steady"
    }

    let kind: ReflectionPeriodKind
    /// "September" or "2025".
    let name: String
    let nextYear: Int

    init(kind: ReflectionPeriodKind, period: WeeklyReflectionPeriod, calendar: Calendar) {
        self.kind = kind
        let year = calendar.component(.year, from: period.start)
        self.nextYear = year + 1
        switch kind {
        case .year:
            name = String(year)
        case .month, .week:
            var style = Date.FormatStyle.dateTime.month(.wide)
            style.timeZone = calendar.timeZone
            name = period.start.formatted(style)
        }
    }

    private var isYear: Bool { kind == .year }

    var emptyHero: String { String(localized: "Not enough to look back on yet.") }

    func notEnough(_ eligibility: WeeklyReflectionEligibility) -> String {
        let thresholds = kind.thresholds
        if eligibility.entryCount < thresholds.minimumEntryCount {
            return String(AttributedString(localized: "I need at least ^[\(thresholds.minimumEntryCount) entry](inflect: true) for a review. \(name) has \(eligibility.entryCount).").characters)
        }
        return String(localized: "I need at least \(thresholds.minimumWordCount) words for a review. \(name) has \(eligibility.wordCount).")
    }

    var heavyHero: String {
        isYear ? String(localized: "This was a heavy year.") : String(localized: "This was a heavy month.")
    }

    var heavySummary: String {
        String(localized: "Some entries were heavy, so I’ve kept this short and didn’t quote them.")
    }

    var heavyNote: String { String(localized: "Some entries were heavy, so I left them out.") }

    var keptWriting: String {
        isYear ? String(localized: "You kept writing through a hard year.") : String(localized: "You kept writing through a hard month.")
    }

    var lightHero: String { String(localized: "A short look back at \(name).") }

    var fewThings: String { String(localized: "A few things stood out in \(name).") }

    func mostlyAbout(_ topic: String, arc: WeeklyReflectionEmotionalArc?) -> String {
        switch arc?.label {
        case ArcLabel.lighter: return String(localized: "\(name) was mostly about \(topic), and it got lighter as it went.")
        case ArcLabel.heavier: return String(localized: "\(name) was mostly about \(topic), and it got heavier as it went.")
        case ArcLabel.steady: return String(localized: "\(name) was mostly about \(topic), and it stayed steady.")
        default: return String(localized: "\(name) was mostly about \(topic).")
        }
    }

    func counts(_ stats: PeriodReviewStats) -> String {
        String(AttributedString(localized: "^[\(stats.entryCount) entry](inflect: true) on ^[\(stats.activeDays) day](inflect: true), about \(stats.wordCount) words.").characters)
    }

    var arcLighter: String {
        isYear ? String(localized: "Your entries got lighter in the second half of the year.") : String(localized: "Your entries got lighter toward the end of the month.")
    }

    var arcHeavier: String {
        isYear ? String(localized: "Your entries got heavier in the second half of the year.") : String(localized: "Your entries got heavier toward the end of the month.")
    }

    var arcSteady: String {
        isYear ? String(localized: "Your mood stayed about the same all year.") : String(localized: "Your mood stayed about the same all month.")
    }

    var heavierParts: String {
        isYear ? String(localized: "Parts of the year were heavier.") : String(localized: "Parts of the month were heavier.")
    }

    var nothingHard: String { String(localized: "Nothing stood out as hard in \(name).") }

    var lookAhead: String {
        isYear ? String(localized: "What do you want more of in \(String(nextYear))?") : String(localized: "What do you want more of next month?")
    }
}
