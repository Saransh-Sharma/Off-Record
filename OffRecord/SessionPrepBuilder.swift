//
//  SessionPrepBuilder.swift
//  OffRecord
//
//  Session Prep: a short, factual summary of a date range to bring to a
//  session with a counselor, coach, or anyone the person chooses. The summary
//  is deterministic (counts, moods, recurring themes, notable changes) and
//  never analyzes high-risk entries. Quotes are the person's own choice: none
//  are included until they pick them, from any of their entries.
//

import Foundation
import JournalFoundation

/// One entry in the chosen range.
struct SessionPrepEntry: Identifiable, Hashable, Sendable {
    let id: UUID
    let date: Date
    /// Text the summary may read: empty for entries excluded from AI or reflection.
    let analysisText: String
    /// The entry's own text, offered as a quote only when the person picks it.
    let quoteText: String
    let mood: Mood
    let wordCount: Int

    init(id: UUID, date: Date, analysisText: String, quoteText: String, mood: Mood, wordCount: Int) {
        self.id = id
        self.date = date
        self.analysisText = analysisText.trimmingCharacters(in: .whitespacesAndNewlines)
        self.quoteText = quoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        self.mood = mood
        self.wordCount = wordCount
    }

    var isHighRisk: Bool {
        JournalRiskClassifier.level(for: quoteText) == .highRiskExcluded
            || JournalRiskClassifier.level(for: analysisText) == .highRiskExcluded
    }
}

struct SessionPrepOptions: Equatable, Sendable {
    var start: Date
    var end: Date
    /// Entries whose excerpt goes in the export. Empty by default.
    var selectedQuoteIDs: Set<UUID> = []
    var bringUp: String = ""
    /// Replace people's names with "someone" everywhere in the export.
    var replaceNames: Bool = true
}

struct SessionPrepMoodCount: Hashable, Sendable {
    let mood: Mood
    let days: Int
}

struct SessionPrepTheme: Hashable, Sendable {
    let title: String
    let entryCount: Int
}

struct SessionPrepSummary: Equatable, Sendable {
    var entryCount = 0
    var activeDays = 0
    var wordCount = 0
    var daysWithMood = 0
    var moodCounts: [SessionPrepMoodCount] = []
    /// -1 heavier, 0 steady, 1 lighter; nil with too few moods to say.
    var moodDirection: Int?
    var themes: [SessionPrepTheme] = []
    var notableChanges: [String] = []
    /// High-risk entries left out of the summary (they can still be quoted by choice).
    var excludedEntryCount = 0
}

struct SessionPrepQuote: Hashable, Sendable {
    let date: Date
    let text: String
}

/// The finished document, ready for Markdown, plain text, or PDF.
struct SessionPrepDocument: Equatable, Sendable {
    struct Section: Equatable, Sendable {
        enum Style: Sendable { case bullets, paragraph, quotes }
        var heading: String
        var style: Style
        var items: [String]
    }

    var title: String
    var dateRange: String
    var sections: [Section]
    var footnotes: [String]
}

enum SessionPrepBuilder {
    static let excerptLength = 400

    /// Every entry in range that can be quoted, newest first. High-risk entries are offered too;
    /// the person decides.
    static func quoteCandidates(_ entries: [SessionPrepEntry]) -> [SessionPrepEntry] {
        entries.filter { !$0.quoteText.isEmpty }.sorted { $0.date > $1.date }
    }

    static func summary(for entries: [SessionPrepEntry], start: Date, end: Date, calendar: Calendar = .current) -> SessionPrepSummary {
        let inRange = entries.filter { $0.date >= start && $0.date <= end }.sorted { $0.date < $1.date }
        var summary = SessionPrepSummary()
        summary.entryCount = inRange.count
        summary.activeDays = Set(inRange.map { calendar.startOfDay(for: $0.date) }).count
        summary.wordCount = inRange.reduce(0) { $0 + $1.wordCount }

        // Moods are what the person logged, one per day (the latest that day).
        var moodByDay: [Date: Mood] = [:]
        for entry in inRange where entry.mood != .none {
            moodByDay[calendar.startOfDay(for: entry.date)] = entry.mood
        }
        summary.daysWithMood = moodByDay.count
        summary.moodCounts = Dictionary(grouping: moodByDay.values, by: { $0 })
            .map { SessionPrepMoodCount(mood: $0.key, days: $0.value.count) }
            .sorted { $0.days == $1.days ? $0.mood.rawValue < $1.mood.rawValue : $0.days > $1.days }
        let dailyValences = moodByDay.sorted { $0.key < $1.key }.map(\.value.valence)
        if dailyValences.count >= 4 {
            let half = dailyValences.count / 2
            let early = dailyValences.prefix(half).reduce(0, +) / Double(half)
            let late = dailyValences.suffix(half).reduce(0, +) / Double(half)
            summary.moodDirection = late - early > 0.25 ? 1 : (early - late > 0.25 ? -1 : 0)
        }

        let highRisk = inRange.filter(\.isHighRisk)
        summary.excludedEntryCount = highRisk.count
        let readable = inRange.filter { !$0.isHighRisk && !$0.analysisText.isEmpty }
        let snapshots = readable.map(snapshot)
        let topics = WeeklyReflectionGenerationService.topTopics(in: snapshots, limit: 6)
        summary.themes = topics.compactMap { topic in
            let count = readable.filter { PeriodReviewGenerator.textContains(topic, in: $0.analysisText) }.count
            return count >= 2 ? SessionPrepTheme(title: topic.prefix(1).uppercased() + topic.dropFirst(), entryCount: count) : nil
        }
        .sorted { $0.entryCount == $1.entryCount ? $0.title < $1.title : $0.entryCount > $1.entryCount }
        summary.notableChanges = notableChanges(inRange: inRange, readable: readable, topics: topics, start: start, end: end, direction: summary.moodDirection)
        return summary
    }

    /// Deterministic changes between the first and second half of the range.
    static func notableChanges(
        inRange: [SessionPrepEntry],
        readable: [SessionPrepEntry],
        topics: [String],
        start: Date,
        end: Date,
        direction: Int?
    ) -> [String] {
        let midpoint = start.addingTimeInterval(end.timeIntervalSince(start) / 2)
        var changes: [String] = []

        let firstCount = inRange.filter { $0.date < midpoint }.count
        let secondCount = inRange.count - firstCount
        if secondCount - firstCount >= 2, Double(secondCount) >= Double(firstCount) * 1.5 {
            changes.append(String(localized: "Wrote more often in the second half: \(secondCount) entries, up from \(firstCount)."))
        } else if firstCount - secondCount >= 2, Double(firstCount) >= Double(secondCount) * 1.5 {
            changes.append(String(localized: "Wrote less often in the second half: \(secondCount) entries, down from \(firstCount)."))
        }

        if direction == 1 {
            changes.append(String(localized: "Moods were lighter in the second half."))
        } else if direction == -1 {
            changes.append(String(localized: "Moods were heavier in the second half."))
        }

        let firstHalf = readable.filter { $0.date < midpoint }
        let secondHalf = readable.filter { $0.date >= midpoint }
        for topic in topics {
            let early = firstHalf.filter { PeriodReviewGenerator.textContains(topic, in: $0.analysisText) }.count
            let late = secondHalf.filter { PeriodReviewGenerator.textContains(topic, in: $0.analysisText) }.count
            let title = topic.prefix(1).uppercased() + topic.dropFirst()
            if early == 0, late >= 2 {
                changes.append(String(localized: "\(title) came up only in the second half."))
            } else if late == 0, early >= 2 {
                changes.append(String(localized: "\(title) came up in the first half, not the second."))
            }
            if changes.count >= 4 { break }
        }
        return Array(changes.prefix(4))
    }

    /// A quote: the first sentences of the entry, up to `excerptLength` characters.
    static func excerpt(_ text: String) -> String {
        let collapsed = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > excerptLength else { return collapsed }
        let prefix = String(collapsed.prefix(excerptLength))
        if let lastStop = prefix.lastIndex(where: { ".!?".contains($0) }), prefix.distance(from: prefix.startIndex, to: lastStop) > excerptLength / 2 {
            return String(prefix[...lastStop])
        }
        return prefix.trimmingCharacters(in: .whitespaces) + "…"
    }

    static func document(
        entries: [SessionPrepEntry],
        options: SessionPrepOptions,
        knownNames: [String] = [],
        deviceNoun: String = "iPhone",
        calendar: Calendar = .current
    ) -> SessionPrepDocument {
        let inRange = entries.filter { $0.date >= options.start && $0.date <= options.end }
        let summary = summary(for: inRange, start: options.start, end: options.end, calendar: calendar)
        let quotes = quoteCandidates(inRange)
            .filter { options.selectedQuoteIDs.contains($0.id) }
            .sorted { $0.date < $1.date }
            .map { SessionPrepQuote(date: $0.date, text: excerpt($0.quoteText)) }
        let bringUp = options.bringUp.trimmingCharacters(in: .whitespacesAndNewlines)

        var sections: [SessionPrepDocument.Section] = []
        var overview = [
            String(AttributedString(localized: "^[\(summary.entryCount) entry](inflect: true) on ^[\(summary.activeDays) day](inflect: true) · \(summary.wordCount.formatted()) words").characters)
        ]
        if summary.daysWithMood > 0 {
            let counts = summary.moodCounts.prefix(4).map { "\($0.mood.displayName.lowercased()) \($0.days)" }.formatted(.list(type: .and))
            overview.append(String(AttributedString(localized: "Moods logged on ^[\(summary.daysWithMood) day](inflect: true): \(counts)").characters))
        } else {
            overview.append(String(localized: "No moods logged."))
        }
        sections.append(.init(heading: String(localized: "Overview", comment: "Session Prep section"), style: .bullets, items: overview))

        if !summary.themes.isEmpty {
            let items = summary.themes.map { String(AttributedString(localized: "\($0.title) · ^[\($0.entryCount) entry](inflect: true)").characters) }
            sections.append(.init(heading: String(localized: "Recurring Themes", comment: "Session Prep section"), style: .bullets, items: items))
        }
        if !summary.notableChanges.isEmpty {
            sections.append(.init(heading: String(localized: "Notable Changes", comment: "Session Prep section"), style: .bullets, items: summary.notableChanges))
        }
        if !bringUp.isEmpty {
            sections.append(.init(heading: String(localized: "What I Want to Bring Up", comment: "Session Prep section; written in the person's voice"), style: .paragraph, items: [bringUp]))
        }
        if !quotes.isEmpty {
            let items = quotes.map { "\($0.date.formatted(date: .abbreviated, time: .omitted)) · \($0.text)" }
            sections.append(.init(heading: String(localized: "From My Entries", comment: "Session Prep section: quotes the person picked"), style: .quotes, items: items))
        }

        var footnotes: [String] = []
        if summary.excludedEntryCount > 0 {
            footnotes.append(String(AttributedString(localized: "^[\(summary.excludedEntryCount) entry](inflect: true) left out of the summary.").characters))
        }
        if options.replaceNames {
            footnotes.append(String(localized: "Names are replaced with \u{201C}someone.\u{201D}"))
        }
        footnotes.append(String(localized: "Made by OffRecord on your \(deviceNoun). Not medical advice.", comment: "Session Prep export footer. The argument is iPhone or iPad."))

        var document = SessionPrepDocument(
            title: String(localized: "Session Prep"),
            dateRange: dateRange(options.start, options.end),
            sections: sections,
            footnotes: footnotes
        )
        if options.replaceNames {
            document = redacted(document, knownNames: knownNames)
        }
        return document
    }

    /// Replaces every known or detected person's name in the document's sections with "someone".
    static func redacted(_ document: SessionPrepDocument, knownNames: [String]) -> SessionPrepDocument {
        let texts = document.sections.flatMap(\.items)
        var names = knownNames.filter { $0.count > 1 }
        for name in ShareableInsightPrivacy.detectedNames(in: texts) where !names.contains(name) {
            names.append(name)
        }
        guard !names.isEmpty else { return document }
        var copy = document
        copy.sections = document.sections.map { section in
            var section = section
            section.items = section.items.map { ShareableInsightPrivacy.redact($0, names: names) }
            return section
        }
        return copy
    }

    static func dateRange(_ start: Date, _ end: Date) -> String {
        if Calendar.current.isDate(start, inSameDayAs: end) {
            return start.formatted(date: .abbreviated, time: .omitted)
        }
        return (start..<max(start, end)).formatted(.interval.month(.abbreviated).day().year())
    }

    // MARK: - Text formats

    static func markdown(_ document: SessionPrepDocument) -> String {
        var lines = ["# \(document.title)", "", document.dateRange, ""]
        for section in document.sections {
            lines.append("## \(section.heading)")
            switch section.style {
            case .bullets: lines += section.items.map { "- \($0)" }
            case .paragraph: lines += section.items
            case .quotes: lines += section.items.flatMap { ["> \($0)", ""] }
            }
            lines.append("")
        }
        lines.append("---")
        lines += document.footnotes.map { "*\($0)*" }
        return lines.joined(separator: "\n")
    }

    static func plainText(_ document: SessionPrepDocument) -> String {
        var lines = [document.title, document.dateRange, ""]
        for section in document.sections {
            lines.append(section.heading.uppercased(with: .current))
            switch section.style {
            case .bullets: lines += section.items.map { "- \($0)" }
            case .paragraph: lines += section.items
            case .quotes: lines += section.items.flatMap { ["\u{201C}\($0)\u{201D}", ""] }
            }
            lines.append("")
        }
        lines += document.footnotes
        return lines.joined(separator: "\n")
    }

    private static func snapshot(_ entry: SessionPrepEntry) -> WeeklyReflectionEntrySnapshot {
        WeeklyReflectionEntrySnapshot(id: entry.id, date: entry.date, updatedAt: entry.date, mood: entry.mood.rawValue, text: entry.analysisText, sourceType: .text)
    }
}

extension SessionPrepEntry {
    /// Reads the summary text through the reflection gate, so entries excluded from AI aren't analyzed.
    @MainActor
    init?(entry: DiaryEntry) {
        guard let id = entry.id else { return nil }
        let date = entry.date ?? entry.createdAt ?? Date()
        let raw = (entry.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let snapshot = WeeklyReflectionEntrySnapshot(entry: entry)
        self.init(
            id: id,
            date: date,
            analysisText: snapshot?.text ?? "",
            quoteText: raw,
            mood: Mood(rawValue: (entry.value(forKey: "mood") as? String) ?? "") ?? .none,
            wordCount: raw.split { $0.isWhitespace || $0.isNewline }.count
        )
    }
}
