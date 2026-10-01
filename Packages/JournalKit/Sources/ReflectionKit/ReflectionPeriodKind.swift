//
//  ReflectionPeriodKind.swift
//  ReflectionKit
//
//  Week, month, and year periods for reflections and reviews. Weekly
//  Reflection keeps its own stored format; monthly and yearly reviews reuse
//  the same period, eligibility, and report vocabulary through this kind.
//

import Foundation

public enum ReflectionPeriodKind: String, Codable, Sendable, CaseIterable, Hashable {
    case week
    case month
    case year
}

/// How much writing a period needs before it gets a full, light, or no review.
public struct ReflectionPeriodThresholds: Hashable, Sendable {
    /// Below this many entries the period gets no review.
    public let minimumEntryCount: Int
    /// Below this many words the period gets no review.
    public let minimumWordCount: Int
    /// A full review needs this many entries, or `fullWordCount` words.
    public let fullEntryCount: Int
    public let fullWordCount: Int

    public init(minimumEntryCount: Int, minimumWordCount: Int, fullEntryCount: Int, fullWordCount: Int) {
        self.minimumEntryCount = minimumEntryCount
        self.minimumWordCount = minimumWordCount
        self.fullEntryCount = fullEntryCount
        self.fullWordCount = fullWordCount
    }
}

extension ReflectionPeriodKind {
    /// Weekly values match `WeeklyReflectionEligibilityEngine`; months and years scale them up.
    public var thresholds: ReflectionPeriodThresholds {
        switch self {
        case .week:
            return ReflectionPeriodThresholds(
                minimumEntryCount: 1,
                minimumWordCount: WeeklyReflectionEligibilityEngine.minimumVisibleWordCount,
                fullEntryCount: WeeklyReflectionEligibilityEngine.fullEntryCount,
                fullWordCount: WeeklyReflectionEligibilityEngine.fullWordCount
            )
        case .month:
            return ReflectionPeriodThresholds(minimumEntryCount: 4, minimumWordCount: 200, fullEntryCount: 8, fullWordCount: 2_000)
        case .year:
            return ReflectionPeriodThresholds(minimumEntryCount: 12, minimumWordCount: 600, fullEntryCount: 40, fullWordCount: 10_000)
        }
    }
}

/// Calendar math for every reflection period. All boundaries come from calendar
/// arithmetic, never fixed second counts, so DST and leap years stay correct.
public enum ReflectionPeriodCalendar {
    /// Weeks start on Monday and the first week of a year has at least 4 days (ISO 8601).
    public static func calendar(from base: Calendar = .current) -> Calendar {
        var calendar = base
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    /// The period of `kind` that contains `date`. `end` is the last second of the period.
    public static func period(
        _ kind: ReflectionPeriodKind,
        containing date: Date,
        calendar baseCalendar: Calendar = .current
    ) -> WeeklyReflectionPeriod {
        let calendar = calendar(from: baseCalendar)
        let start: Date
        let nextStart: Date?
        switch kind {
        case .week:
            let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
            start = calendar.date(from: components).map { calendar.startOfDay(for: $0) } ?? calendar.startOfDay(for: date)
            return WeeklyReflectionPeriod(
                start: start,
                end: calendar.date(byAdding: DateComponents(day: 7, second: -1), to: start) ?? date
            )
        case .month:
            let components = calendar.dateComponents([.year, .month], from: date)
            start = calendar.date(from: components).map { calendar.startOfDay(for: $0) } ?? calendar.startOfDay(for: date)
            nextStart = calendar.date(byAdding: .month, value: 1, to: start)
        case .year:
            let components = calendar.dateComponents([.year], from: date)
            start = calendar.date(from: components).map { calendar.startOfDay(for: $0) } ?? calendar.startOfDay(for: date)
            nextStart = calendar.date(byAdding: .year, value: 1, to: start)
        }
        let end = nextStart.map { calendar.startOfDay(for: $0).addingTimeInterval(-1) } ?? date
        return WeeklyReflectionPeriod(start: start, end: end)
    }

    /// The month `month` (1–12) of `year`, or nil when either is out of range.
    public static func month(year: Int, month: Int, calendar baseCalendar: Calendar = .current) -> WeeklyReflectionPeriod? {
        guard (1...9_999).contains(year), (1...12).contains(month) else { return nil }
        let calendar = calendar(from: baseCalendar)
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: 1, hour: 12)) else { return nil }
        return period(.month, containing: date, calendar: calendar)
    }

    /// The calendar year `year`, or nil when it is out of range.
    public static func year(_ year: Int, calendar baseCalendar: Calendar = .current) -> WeeklyReflectionPeriod? {
        guard (1...9_999).contains(year) else { return nil }
        let calendar = calendar(from: baseCalendar)
        guard let date = calendar.date(from: DateComponents(year: year, month: 6, day: 1, hour: 12)) else { return nil }
        return period(.year, containing: date, calendar: calendar)
    }

    /// The most recent period of `kind` that ended before the one containing `now`.
    public static func lastCompletedPeriod(
        _ kind: ReflectionPeriodKind,
        before now: Date,
        calendar: Calendar = .current
    ) -> WeeklyReflectionPeriod {
        let current = period(kind, containing: now, calendar: calendar)
        return period(kind, containing: current.start.addingTimeInterval(-1), calendar: calendar)
    }

    /// Up to `count` completed periods of `kind` before `now`, newest first.
    public static func completedPeriods(
        _ kind: ReflectionPeriodKind,
        before now: Date,
        count: Int,
        calendar: Calendar = .current
    ) -> [WeeklyReflectionPeriod] {
        var result: [WeeklyReflectionPeriod] = []
        var cursor = now
        for _ in 0..<max(0, count) {
            let previous = lastCompletedPeriod(kind, before: cursor, calendar: calendar)
            result.append(previous)
            cursor = previous.start
        }
        return result
    }

    /// A stable key for a period, such as "2026-09" for a month or "2026" for a year.
    public static func key(for period: WeeklyReflectionPeriod, kind: ReflectionPeriodKind, calendar baseCalendar: Calendar = .current) -> String {
        let calendar = calendar(from: baseCalendar)
        let components = calendar.dateComponents([.year, .month, .day, .yearForWeekOfYear, .weekOfYear], from: period.start)
        switch kind {
        case .week:
            return String(format: "%04d-W%02d", components.yearForWeekOfYear ?? 0, components.weekOfYear ?? 0)
        case .month:
            return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
        case .year:
            return String(format: "%04d", components.year ?? 0)
        }
    }

    /// Year in Review opens on December 1 for the current year, anytime for past
    /// years, and never for a year without entries or one that hasn't started.
    public static func isYearInReviewAvailable(
        year: Int,
        now: Date,
        hasEntries: Bool,
        calendar: Calendar = .current
    ) -> Bool {
        guard hasEntries else { return false }
        let currentYear = calendar.component(.year, from: now)
        if year < currentYear { return true }
        if year > currentYear { return false }
        return calendar.component(.month, from: now) == 12
    }
}

extension WeeklyReflectionEligibilityEngine {
    /// Eligibility for any period kind. `.week` gives the same result as
    /// `evaluate(entries:in:)`. Entries without text still count when they
    /// carry a word count (entries excluded from AI keep their counts).
    public static func evaluate(
        entries: [WeeklyReflectionEntrySnapshot],
        in period: WeeklyReflectionPeriod,
        kind: ReflectionPeriodKind
    ) -> WeeklyReflectionEligibility {
        let thresholds = kind.thresholds
        let eligible = entries.filter { period.contains($0.date) && (!$0.text.isEmpty || $0.wordCount > 0) }
        let words = eligible.reduce(0) { $0 + $1.wordCount }
        let kindResult: WeeklyReflectionEligibilityKind
        if eligible.count < thresholds.minimumEntryCount || words < thresholds.minimumWordCount {
            kindResult = .empty
        } else if eligible.count >= thresholds.fullEntryCount || words >= thresholds.fullWordCount {
            kindResult = .full
        } else {
            kindResult = .light
        }
        return WeeklyReflectionEligibility(kind: kindResult, entryCount: eligible.count, wordCount: words)
    }
}
