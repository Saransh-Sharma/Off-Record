import CoreData
import Foundation
import NaturalLanguage

extension Mood: @unchecked Sendable {}

struct JournalEntrySnapshot: Identifiable, Equatable, @unchecked Sendable {
    let id: String
    let uuid: UUID?
    let objectIDURI: String
    let date: Date?
    let text: String
    let mood: Mood
    let wordCount: Int
    let duration: Double
    let isStarred: Bool
    let hasAudio: Bool
    let photoCount: Int

    var isStartedEntry: Bool {
        wordCount > 0 || hasAudio || photoCount > 0 || mood != .none
    }

    init(
        id: String,
        uuid: UUID?,
        objectIDURI: String,
        date: Date?,
        text: String,
        mood: Mood,
        wordCount: Int,
        duration: Double,
        isStarred: Bool,
        hasAudio: Bool,
        photoCount: Int
    ) {
        self.id = id
        self.uuid = uuid
        self.objectIDURI = objectIDURI
        self.date = date
        self.text = text
        self.mood = mood
        self.wordCount = wordCount
        self.duration = duration
        self.isStarred = isStarred
        self.hasAudio = hasAudio
        self.photoCount = photoCount
    }

    @MainActor
    init(entry: DiaryEntry) {
        let uuid = entry.id
        let text = (entry.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let moodString = (entry.value(forKey: "mood") as? String) ?? ""
        let mood = Mood(rawValue: moodString) ?? .none
        let photoCount = entry.photos?.count ?? 0

        self.uuid = uuid
        self.objectIDURI = entry.objectID.uriRepresentation().absoluteString
        self.id = uuid?.uuidString ?? objectIDURI
        self.date = entry.date
        self.text = text
        self.mood = mood
        self.wordCount = text.split { $0.isWhitespace || $0.isNewline }.count
        self.duration = entry.duration
        self.isStarred = entry.isStarred
        self.hasAudio = entry.hasStartedEntryAudio
        self.photoCount = photoCount
    }
}

extension Sequence where Element == DiaryEntry {
    @MainActor
    var journalSnapshots: [JournalEntrySnapshot] {
        map(JournalEntrySnapshot.init(entry:)).filter(\.isStartedEntry)
    }
}

struct JournalInsightSummary: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let description: String
    let icon: String
    let colorName: String
    /// Plain-language note on how the insight was derived.
    var rationale: String = ""
    /// `JournalEntrySnapshot.id` values of the entries that support the insight.
    var supportingEntryIDs: [String] = []
}

struct JournalDayActivity: Identifiable, Equatable, Sendable {
    let id: Date
    let date: Date
    let label: String
    let hasEntry: Bool
}

struct JournalMoodCount: Identifiable, Equatable, Sendable {
    let mood: Mood
    let count: Int

    var id: Mood { mood }
}

struct JournalMoodChartPoint: Identifiable, Equatable, Sendable {
    let date: Date
    let mood: Mood?

    var id: Date { date }
}

struct JournalGoalProgress: Equatable, Sendable {
    let isEnabled: Bool
    let weeklyTarget: Int
    let count: Int
    let progress: Double
    let daysRemaining: Int

    static let empty = JournalGoalProgress(
        isEnabled: false,
        weeklyTarget: 3,
        count: 0,
        progress: 0,
        daysRemaining: 0
    )
}

struct JournalStatsSnapshot: Equatable, Sendable {
    let entryCount: Int
    let currentStreak: Int
    let longestStreak: Int
    let entriesThisMonth: Int
    let entriesThisYear: Int
    let daysRecordedThisYear: Int
    let last7Days: [JournalDayActivity]
    let moodCounts: [JournalMoodCount]
    let moodChartData: [JournalMoodChartPoint]
    let totalWords: Int
    let avgWordsPerEntry: Int
    let starredCount: Int
    let audioCount: Int
    let insights: [JournalInsightSummary]
    let weeklySummary: String
    let goal: JournalGoalProgress
    let availableYears: [Int]

    var isEmpty: Bool { entryCount == 0 }

    static let empty = JournalStatsSnapshot(
        entryCount: 0,
        currentStreak: 0,
        longestStreak: 0,
        entriesThisMonth: 0,
        entriesThisYear: 0,
        daysRecordedThisYear: 0,
        last7Days: [],
        moodCounts: [],
        moodChartData: [],
        totalWords: 0,
        avgWordsPerEntry: 0,
        starredCount: 0,
        audioCount: 0,
        insights: [],
        weeklySummary: "No entries this week. Start journaling to see your weekly summary!",
        goal: .empty,
        availableYears: []
    )
}

actor JournalAnalyticsWorker {
    static let shared = JournalAnalyticsWorker()

    func makeStats(
        from entries: [JournalEntrySnapshot],
        now: Date,
        weeklyTarget: Int,
        goalEnabled: Bool
    ) -> JournalStatsSnapshot {
        let token = PerformanceSignposts.begin("JournalStatsAnalytics")
        defer { PerformanceSignposts.end(token) }

        let sortedEntries = entries.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        let calendar = Calendar.current
        let days = Set(sortedEntries.compactMap { entry -> Date? in
            guard let date = entry.date else { return nil }
            return calendar.startOfDay(for: date)
        })
        let today = calendar.startOfDay(for: now)
        let currentYear = calendar.component(.year, from: now)
        let currentMonthEntries = sortedEntries.filter { entry in
            guard let date = entry.date else { return false }
            return calendar.isDate(date, equalTo: now, toGranularity: .month)
        }
        let currentYearEntries = sortedEntries.filter { entry in
            guard let date = entry.date else { return false }
            return calendar.component(.year, from: date) == currentYear
        }
        let totalWords = sortedEntries.reduce(0) { $0 + $1.wordCount }
        let weeklyCount = entriesThisWeek(entries: sortedEntries, calendar: calendar, now: now)

        return JournalStatsSnapshot(
            entryCount: sortedEntries.count,
            currentStreak: currentStreak(days: days, calendar: calendar, today: today),
            longestStreak: longestStreak(days: days, calendar: calendar),
            entriesThisMonth: currentMonthEntries.count,
            entriesThisYear: currentYearEntries.count,
            daysRecordedThisYear: days.filter { calendar.component(.year, from: $0) == currentYear }.count,
            last7Days: last7Days(days: days, calendar: calendar, today: today),
            moodCounts: moodCounts(from: sortedEntries),
            moodChartData: moodChartData(from: sortedEntries, calendar: calendar, today: today),
            totalWords: totalWords,
            avgWordsPerEntry: sortedEntries.isEmpty ? 0 : totalWords / sortedEntries.count,
            starredCount: sortedEntries.filter(\.isStarred).count,
            audioCount: sortedEntries.filter(\.hasAudio).count,
            insights: makeInsights(from: sortedEntries, calendar: calendar, now: now),
            weeklySummary: weeklySummary(from: sortedEntries, calendar: calendar, now: now),
            goal: JournalGoalProgress(
                isEnabled: goalEnabled,
                weeklyTarget: weeklyTarget,
                count: weeklyCount,
                progress: weeklyTarget > 0 ? min(1, Double(weeklyCount) / Double(weeklyTarget)) : 0,
                daysRemaining: daysRemainingInWeek(calendar: calendar, now: now)
            ),
            availableYears: Array(Set(sortedEntries.compactMap { entry -> Int? in
                guard let date = entry.date else { return nil }
                return calendar.component(.year, from: date)
            })).sorted()
        )
    }

    private func currentStreak(days: Set<Date>, calendar: Calendar, today: Date) -> Int {
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

    private func longestStreak(days: Set<Date>, calendar: Calendar) -> Int {
        let sortedDays = days.sorted(by: >)
        guard !sortedDays.isEmpty else { return 0 }
        var longest = 1
        var current = 1

        for index in 1..<sortedDays.count {
            let diff = calendar.dateComponents([.day], from: sortedDays[index], to: sortedDays[index - 1]).day ?? 0
            if diff == 1 {
                current += 1
                longest = max(longest, current)
            } else {
                current = 1
            }
        }
        return longest
    }

    private func last7Days(days: Set<Date>, calendar: Calendar, today: Date) -> [JournalDayActivity] {
        (0..<7).compactMap { offset -> JournalDayActivity? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let label = String(date.formatted(.dateTime.weekday(.abbreviated)).prefix(1))
            return JournalDayActivity(id: date, date: date, label: label, hasEntry: days.contains(date))
        }
        .reversed()
    }

    private func moodCounts(from entries: [JournalEntrySnapshot]) -> [JournalMoodCount] {
        var counts: [Mood: Int] = [:]
        for entry in entries where entry.mood != .none {
            counts[entry.mood, default: 0] += 1
        }
        return counts
            .map { JournalMoodCount(mood: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    private func moodChartData(from entries: [JournalEntrySnapshot], calendar: Calendar, today: Date) -> [JournalMoodChartPoint] {
        (0..<14).compactMap { offset -> JournalMoodChartPoint? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let entry = entries.first { entry in
                guard let entryDate = entry.date else { return false }
                return calendar.isDate(entryDate, inSameDayAs: date)
            }
            return JournalMoodChartPoint(date: date, mood: entry?.mood)
        }
        .reversed()
    }

    private func entriesThisWeek(entries: [JournalEntrySnapshot], calendar: Calendar, now: Date) -> Int {
        guard let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) else { return 0 }
        return Set(entries.compactMap { entry -> Date? in
            guard let date = entry.date, date >= weekStart else { return nil }
            return calendar.startOfDay(for: date)
        }).count
    }

    private func daysRemainingInWeek(calendar: Calendar, now: Date) -> Int {
        8 - calendar.component(.weekday, from: now)
    }

    private func makeInsights(from entries: [JournalEntrySnapshot], calendar: Calendar, now: Date) -> [JournalInsightSummary] {
        InsightsEngine.makeInsights(from: entries, calendar: calendar, now: now)
    }

    private func weeklySummary(from entries: [JournalEntrySnapshot], calendar: Calendar, now: Date) -> String {
        let weekEntries = entries.filter { entry in
            guard let date = entry.date else { return false }
            return (calendar.dateComponents([.day], from: date, to: now).day ?? 0) <= 7
        }

        guard !weekEntries.isEmpty else {
            return "No entries this week. Start journaling to see your weekly summary!"
        }

        var summary = "This week you wrote \(weekEntries.count) \(weekEntries.count == 1 ? "entry" : "entries") with \(weekEntries.reduce(0) { $0 + $1.wordCount }) words. "
        let moods = weekEntries.map(\.mood).filter { $0 != .none }
        if !moods.isEmpty {
            let moodCounts = Dictionary(grouping: moods, by: { $0 }).mapValues(\.count)
            if let topMood = moodCounts.max(by: { $0.value < $1.value }) {
                summary += "Your most common mood was \(topMood.key.displayName.lowercased()). "
            }
        }
        return summary
    }
}
