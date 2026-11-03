//
//  PeriodReviewModels.swift
//  ReflectionKit
//
//  Month and year reviews. A review wraps the shared reflection report
//  (summary, themes, safety level, included entries) and adds the numbers a
//  longer look back needs. Weekly reports are stored separately and unchanged.
//

import Foundation

/// One day in a review's mood calendar. `mood` is the stored mood raw value, empty when none was logged.
public struct PeriodReviewMoodDay: Codable, Hashable, Sendable {
    public var day: Date
    public var mood: String

    public init(day: Date, mood: String) {
        self.day = day
        self.mood = mood
    }
}

/// Mood across one slice of a review: a week of a month, or a month of a year.
public struct PeriodReviewMoodBucket: Codable, Hashable, Sendable, Identifiable {
    public var start: Date
    /// Most common logged mood raw value, or nil when no mood was logged.
    public var dominantMood: String?
    /// Average mood valence (-1...1), or nil when no mood was logged.
    public var averageValence: Double?
    public var entryCount: Int

    public var id: Date { start }

    public init(start: Date, dominantMood: String?, averageValence: Double?, entryCount: Int) {
        self.start = start
        self.dominantMood = dominantMood
        self.averageValence = averageValence
        self.entryCount = entryCount
    }
}

/// A person or topic and how many entries in the period mention it.
public struct PeriodReviewMention: Codable, Hashable, Sendable, Identifiable {
    /// Knowledge-graph node id when the mention came from Friday's memory; nil for text signals.
    public var nodeID: String?
    public var label: String
    public var entryCount: Int

    public var id: String { nodeID ?? "text:\(label.lowercased())" }

    public init(nodeID: String?, label: String, entryCount: Int) {
        self.nodeID = nodeID
        self.label = label
        self.entryCount = entryCount
    }
}

public enum PeriodReviewHighlightReason: String, Codable, Hashable, Sendable {
    case starred
    case cited
    case mentions
}

/// An entry that mattered: starred, cited by reflections, or full of the period's top people and topics.
public struct PeriodReviewHighlight: Codable, Hashable, Sendable, Identifiable {
    public var entryId: UUID
    public var date: Date
    public var snippet: String
    public var reasons: [PeriodReviewHighlightReason]
    public var score: Int

    public var id: UUID { entryId }

    public init(entryId: UUID, date: Date, snippet: String, reasons: [PeriodReviewHighlightReason], score: Int) {
        self.entryId = entryId
        self.date = date
        self.snippet = snippet
        self.reasons = reasons
        self.score = score
    }
}

public struct PeriodReviewStats: Codable, Hashable, Sendable {
    public var entryCount: Int
    public var activeDays: Int
    public var wordCount: Int
    public var recordedSeconds: Double
    public var photoCount: Int
    public var starredCount: Int
    public var moodDays: [PeriodReviewMoodDay]
    public var moodBuckets: [PeriodReviewMoodBucket]
    public var topPeople: [PeriodReviewMention]
    public var topTopics: [PeriodReviewMention]
    public var highlights: [PeriodReviewHighlight]
    /// Entries left out of every generated line because they were high risk.
    public var excludedEntryCount: Int

    public init(
        entryCount: Int,
        activeDays: Int,
        wordCount: Int,
        recordedSeconds: Double,
        photoCount: Int,
        starredCount: Int,
        moodDays: [PeriodReviewMoodDay],
        moodBuckets: [PeriodReviewMoodBucket],
        topPeople: [PeriodReviewMention],
        topTopics: [PeriodReviewMention],
        highlights: [PeriodReviewHighlight],
        excludedEntryCount: Int
    ) {
        self.entryCount = entryCount
        self.activeDays = activeDays
        self.wordCount = wordCount
        self.recordedSeconds = recordedSeconds
        self.photoCount = photoCount
        self.starredCount = starredCount
        self.moodDays = moodDays
        self.moodBuckets = moodBuckets
        self.topPeople = topPeople
        self.topTopics = topTopics
        self.highlights = highlights
        self.excludedEntryCount = excludedEntryCount
    }

    public static let empty = PeriodReviewStats(
        entryCount: 0, activeDays: 0, wordCount: 0, recordedSeconds: 0, photoCount: 0, starredCount: 0,
        moodDays: [], moodBuckets: [], topPeople: [], topTopics: [], highlights: [], excludedEntryCount: 0
    )

    public var recordedMinutes: Int { Int((recordedSeconds / 60).rounded()) }
}

/// A Month in Review or Year in Review.
public struct PeriodReview: Identifiable, Codable, Hashable, Sendable {
    public var kind: ReflectionPeriodKind
    /// "2026-09" for a month, "2026" for a year (see `ReflectionPeriodCalendar.key`).
    public var periodKey: String
    public var report: WeeklyReflectionReport
    public var stats: PeriodReviewStats

    public var id: UUID { report.id }
    public var period: WeeklyReflectionPeriod { report.period }

    public init(kind: ReflectionPeriodKind, periodKey: String, report: WeeklyReflectionReport, stats: PeriodReviewStats) {
        self.kind = kind
        self.periodKey = periodKey
        self.report = report
        self.stats = stats
    }

    /// Whether any entry in the period was left out for safety; the review then shows support.
    public var touchesHighRiskContent: Bool {
        report.safetyLevel == .highRiskExcluded || stats.excludedEntryCount > 0
    }
}
