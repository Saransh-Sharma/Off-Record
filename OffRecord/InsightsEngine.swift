//
//  InsightsEngine.swift
//  OffRecord
//
//  Explainable, on-device insights for the Insights tab.
//
//  Every insight carries the IDs of the entries that support it plus a short
//  plain-language rationale, so the UI can answer "Why am I seeing this?".
//  Analysis uses Apple's NaturalLanguage framework. Copy states facts and
//  numbers, not diagnoses.
//

import Foundation
import NaturalLanguage

enum InsightsEngine {
    /// Upper bound on how many supporting entries an insight cites.
    static let maximumEvidenceCount = 12

    private static let positiveMoods: Set<Mood> = [.happy, .excited, .grateful, .calm]

    /// Builds insights from snapshots sorted newest first.
    static func makeInsights(
        from entries: [JournalEntrySnapshot],
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> [JournalInsightSummary] {
        var insights: [JournalInsightSummary] = []
        if let insight = streakInsight(entries: entries, calendar: calendar, now: now) { insights.append(insight) }
        if let insight = moodInsight(entries: entries, calendar: calendar, now: now) { insights.append(insight) }
        if let insight = writingPatternInsight(entries: entries, calendar: calendar) { insights.append(insight) }
        if let insight = productivityInsight(entries: entries, calendar: calendar, now: now) { insights.append(insight) }
        if let insight = milestoneInsight(entries: entries) { insights.append(insight) }
        if let insight = sentimentInsight(entries: entries) { insights.append(insight) }
        return insights
    }

    // MARK: - Streak

    static func currentStreak(days: Set<Date>, calendar: Calendar, today: Date) -> Int {
        var checkDate = today
        if !days.contains(checkDate) {
            checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
            guard days.contains(checkDate) else { return 0 }
        }

        var streak = 0
        while days.contains(checkDate) {
            streak += 1
            checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
        }
        return streak
    }

    private static func streakInsight(entries: [JournalEntrySnapshot], calendar: Calendar, now: Date) -> JournalInsightSummary? {
        let today = calendar.startOfDay(for: now)
        let days = Set(entries.compactMap { $0.date.map { calendar.startOfDay(for: $0) } })
        let streak = currentStreak(days: days, calendar: calendar, today: today)
        let hasToday = days.contains(today)

        let streakStart = calendar.date(byAdding: .day, value: -(streak + (hasToday ? 0 : 1)), to: today) ?? today
        let streakEntries = entries.filter { entry in
            guard let date = entry.date else { return false }
            return date >= streakStart
        }
        let rationale = "Days in a row with at least one entry."

        if streak >= 7 {
            return JournalInsightSummary(
                id: "streak-7",
                title: "On a streak",
                description: "\(streak) days in a row.",
                icon: "flame.fill",
                colorName: "orange",
                rationale: rationale,
                supportingEntryIDs: evidenceIDs(streakEntries)
            )
        } else if streak >= 3 {
            return JournalInsightSummary(
                id: "streak-3",
                title: "Building a habit",
                description: "\(streak) days in a row so far.",
                icon: "arrow.up.right",
                colorName: "green",
                rationale: rationale,
                supportingEntryIDs: evidenceIDs(streakEntries)
            )
        } else if !hasToday && streak == 0 {
            return JournalInsightSummary(
                id: "write-today",
                title: "Nothing yet today",
                description: "A sentence counts.",
                icon: "pencil.line",
                colorName: "blue"
            )
        }
        return nil
    }

    // MARK: - Mood

    private static func moodInsight(entries: [JournalEntrySnapshot], calendar: Calendar, now: Date) -> JournalInsightSummary? {
        let recent = entries.filter { entry in
            guard let date = entry.date, entry.mood != .none else { return false }
            return (calendar.dateComponents([.day], from: date, to: now).day ?? 0) <= 7
        }
        guard recent.count >= 3 else { return nil }

        let positive = recent.filter { positiveMoods.contains($0.mood) }
        let positiveRatio = Double(positive.count) / Double(recent.count)
        let rationale = "Based on \(recent.count) moods from the last 7 days."

        if positiveRatio >= 0.7 {
            return JournalInsightSummary(
                id: "positive-week",
                title: "A good week",
                description: "\(Int(positiveRatio * 100))% of your moods this week were positive.",
                icon: "sun.max.fill",
                colorName: "yellow",
                rationale: rationale,
                supportingEntryIDs: evidenceIDs(positive)
            )
        } else if positiveRatio <= 0.3 {
            let heavier = recent.filter { !positiveMoods.contains($0.mood) }
            return JournalInsightSummary(
                id: "tough-week",
                title: "A harder week",
                description: "More of your moods this week were low.",
                icon: "heart.fill",
                colorName: "pink",
                rationale: rationale,
                supportingEntryIDs: evidenceIDs(heavier)
            )
        }
        return nil
    }

    // MARK: - Writing Patterns

    private static func writingPatternInsight(entries: [JournalEntrySnapshot], calendar: Calendar) -> JournalInsightSummary? {
        var morning: [JournalEntrySnapshot] = []
        var evening: [JournalEntrySnapshot] = []
        let sample = entries.prefix(30)

        for entry in sample {
            guard let date = entry.date else { continue }
            let hour = calendar.component(.hour, from: date)
            if hour < 12 {
                morning.append(entry)
            } else if hour >= 18 {
                evening.append(entry)
            }
        }

        let rationale = String(AttributedString(localized: "Based on when you wrote your last ^[\(sample.count) entry](inflect: true).").characters)
        if morning.count > evening.count * 2 {
            return JournalInsightSummary(
                id: "morning-writer",
                title: "Morning writer",
                description: "You usually journal before noon.",
                icon: "sunrise.fill",
                colorName: "orange",
                rationale: rationale,
                supportingEntryIDs: evidenceIDs(morning)
            )
        } else if evening.count > morning.count * 2 {
            return JournalInsightSummary(
                id: "evening-writer",
                title: "Evening writer",
                description: "You usually journal after 6 PM.",
                icon: "moon.stars.fill",
                colorName: "indigo",
                rationale: rationale,
                supportingEntryIDs: evidenceIDs(evening)
            )
        }
        return nil
    }

    // MARK: - Productivity

    private static func productivityInsight(entries: [JournalEntrySnapshot], calendar: Calendar, now: Date) -> JournalInsightSummary? {
        let thisMonth = entries.filter { entry in
            guard let date = entry.date else { return false }
            return calendar.isDate(date, equalTo: now, toGranularity: .month)
        }
        guard let lastMonthDate = calendar.date(byAdding: .month, value: -1, to: now) else { return nil }
        let lastMonthWords = entries.reduce(0) { total, entry in
            guard let date = entry.date, calendar.isDate(date, equalTo: lastMonthDate, toGranularity: .month) else { return total }
            return total + entry.wordCount
        }
        let thisMonthWords = thisMonth.reduce(0) { $0 + $1.wordCount }

        guard lastMonthWords > 0, thisMonthWords > lastMonthWords else { return nil }
        let increase = Int(Double(thisMonthWords - lastMonthWords) / Double(lastMonthWords) * 100)
        guard increase >= 20 else { return nil }

        return JournalInsightSummary(
            id: "writing-more",
            title: "Writing more",
            description: "You’ve written \(increase)% more this month.",
            icon: "chart.line.uptrend.xyaxis",
            colorName: "green",
            rationale: "\(thisMonthWords) words this month vs. \(lastMonthWords) last month.",
            supportingEntryIDs: evidenceIDs(thisMonth.sorted { $0.wordCount > $1.wordCount })
        )
    }

    // MARK: - Milestones

    private static func milestoneInsight(entries: [JournalEntrySnapshot]) -> JournalInsightSummary? {
        for milestone in [10, 25, 50, 100, 200, 365, 500, 1000] where entries.count >= milestone && entries.count < milestone + 5 {
            // Entries are newest first, so the milestone entry sits `milestone` places from the oldest.
            let milestoneEntry = entries[entries.count - milestone]
            let description = milestoneEntry.date.map {
                "Your \(milestone)th entry was on \($0.formatted(date: .long, time: .omitted))."
            } ?? "You’ve saved \(milestone) entries."
            return JournalInsightSummary(
                id: "milestone-\(milestone)",
                title: "\(milestone) entries",
                description: description,
                icon: "trophy.fill",
                colorName: "yellow",
                supportingEntryIDs: [milestoneEntry.id]
            )
        }
        return nil
    }

    // MARK: - Sentiment

    private static func sentimentInsight(entries: [JournalEntrySnapshot]) -> JournalInsightSummary? {
        let recent = entries.prefix(10).filter { !$0.text.isEmpty }
        guard !recent.isEmpty else { return nil }

        let tagger = NLTagger(tagSchemes: [.sentimentScore])
        var scored: [(entry: JournalEntrySnapshot, score: Double)] = []
        for entry in recent {
            tagger.string = entry.text
            let (sentiment, _) = tagger.tag(at: entry.text.startIndex, unit: .paragraph, scheme: .sentimentScore)
            let score = sentiment.flatMap { Double($0.rawValue) } ?? 0
            scored.append((entry, score))
        }

        let average = scored.reduce(0) { $0 + $1.score } / Double(scored.count)
        let rationale = String(AttributedString(localized: "Estimated from the wording of your last ^[\(scored.count) entry](inflect: true).").characters)
        if average > 0.3 {
            return JournalInsightSummary(
                id: "positive-writing",
                title: "Upbeat lately",
                description: "Your recent entries read positive.",
                icon: "face.smiling.fill",
                colorName: "green",
                rationale: rationale,
                supportingEntryIDs: evidenceIDs(scored.filter { $0.score > 0 }.sorted { $0.score > $1.score }.map(\.entry))
            )
        } else if average < -0.3 {
            return JournalInsightSummary(
                id: "gratitude",
                title: "Heavier lately",
                description: "Your recent entries read heavier. Want to note one good thing today?",
                icon: "heart.text.square.fill",
                colorName: "pink",
                rationale: rationale,
                supportingEntryIDs: evidenceIDs(scored.filter { $0.score < 0 }.sorted { $0.score < $1.score }.map(\.entry))
            )
        }
        return nil
    }

    // MARK: - Helpers

    private static func evidenceIDs<S: Sequence>(_ entries: S) -> [String] where S.Element == JournalEntrySnapshot {
        var seen = Set<String>()
        var ids: [String] = []
        for entry in entries where seen.insert(entry.id).inserted {
            ids.append(entry.id)
            if ids.count == maximumEvidenceCount { break }
        }
        return ids
    }
}
