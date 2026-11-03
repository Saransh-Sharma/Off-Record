//
//  KnowledgeMentionAggregator.swift
//  OffRecord
//
//  The data behind a person, place, or topic page in Friday's My World:
//  which entries mention the name, how often by month, the mood of those
//  entries, and the first and last mention. It scans entry text for the name
//  as written in the journal, because the graph's own first and last dates
//  are learning times, not entry dates.
//
//  Only entries Friday may read count: entries kept out of Friday and
//  high-risk entries are dropped by the same gate the profile rebuild uses
//  (`FridayLearningInput`), and a forgotten item has no page content at all.
//  A rename changes the title only; entries still say the original name.
//

import Foundation
import JournalFoundation

struct KnowledgeMention: Identifiable, Equatable, Sendable {
    let entryID: UUID
    let date: Date
    let mood: String?
    /// The sentence with the first mention, shortened when long.
    let snippet: String
    /// Times the name appears in the entry.
    let occurrences: Int

    var id: UUID { entryID }

    /// The mention as one of Friday's evidence chips.
    var evidence: EvidenceReference {
        EvidenceReference(
            id: entryID.uuidString,
            entryID: entryID,
            date: date,
            mood: mood,
            snippet: snippet,
            chunkText: snippet,
            score: 1,
            matchReason: .entity
        )
    }
}

struct KnowledgeMonthCount: Identifiable, Equatable, Sendable {
    /// Start of the month.
    let month: Date
    /// Entries in that month that mention the name.
    let count: Int

    var id: Date { month }
}

struct KnowledgeMoodCount: Identifiable, Equatable, Sendable {
    let mood: Mood
    let count: Int

    var id: String { mood.rawValue }
}

struct KnowledgeMentionSummary: Equatable, Sendable {
    /// Newest first.
    let mentions: [KnowledgeMention]
    /// Oldest first, with empty months filled in; at most `KnowledgeMentionAggregator.chartMonths`.
    let months: [KnowledgeMonthCount]
    /// Most common first. Entries without a mood are left out.
    let moods: [KnowledgeMoodCount]

    static let empty = KnowledgeMentionSummary(mentions: [], months: [], moods: [])

    var entryCount: Int { mentions.count }
    var firstMention: Date? { mentions.last?.date }
    var lastMention: Date? { mentions.first?.date }

    /// The month with the most mentions, latest on a tie.
    var busiestMonth: KnowledgeMonthCount? {
        months.filter { $0.count > 0 }.max { lhs, rhs in
            lhs.count != rhs.count ? lhs.count < rhs.count : lhs.month < rhs.month
        }
    }
}

/// What a page shows for one remembered item.
struct KnowledgePageContent: Equatable, Sendable {
    /// The name Friday uses: the rename when there is one.
    let title: String
    /// The name as written in the journal, when it differs from the title.
    let writtenAs: String?
    let summary: KnowledgeMentionSummary
}

enum KnowledgeMentionAggregator {
    static let chartMonths = 12
    static let maximumSnippetLength = 180

    /// Page content for `node`, or nil when the item is forgotten.
    @MainActor
    static func content(
        for node: PersonalKnowledgeGraph.KnowledgeNode,
        entries: [DiaryEntry],
        isForgotten: Bool,
        alias: String?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> KnowledgePageContent? {
        guard !isForgotten else { return nil }
        let rename = alias?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = (rename?.isEmpty == false ? rename : nil) ?? node.label
        let inputs = readableInputs(mentioning: node.label, in: entries)
        return KnowledgePageContent(
            title: title,
            writtenAs: title == node.label ? nil : node.label,
            summary: summarize(label: node.label, type: node.type, inputs: inputs, now: now, calendar: calendar)
        )
    }

    /// Entries that might mention `label` and that Friday may read. The cheap text
    /// check runs first, so the safety screen only sees likely matches.
    @MainActor
    static func readableInputs(mentioning label: String, in entries: [DiaryEntry]) -> [FridayLearningInput] {
        let needle = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        return entries
            .filter { !$0.isDeleted && ($0.text ?? "").range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
            .compactMap(FridayLearningInput.init(entry:))
            .filter { JournalRiskClassifier.responseMode(for: $0.text) != .supportOnly }
    }

    /// Counts whole-word mentions of `label`. Names of people and places must keep
    /// their capital letter, so "Will" doesn't match "will"; topics match in any case.
    static func summarize(
        label: String,
        type: PersonalKnowledgeGraph.KnowledgeNode.NodeType,
        inputs: [FridayLearningInput],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> KnowledgeMentionSummary {
        let needle = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty, let expression = mentionExpression(for: needle) else { return .empty }
        let requiresCapital = (type == .person || type == .place) && (needle.first?.isUppercase ?? false)

        var mentions: [KnowledgeMention] = []
        for input in inputs {
            let text = input.text
            let matches = expression.matches(in: text, range: NSRange(text.startIndex..., in: text))
                .compactMap { Range($0.range, in: text) }
                .filter { !requiresCapital || (text[$0].first?.isUppercase ?? false) }
            guard let first = matches.first else { continue }
            mentions.append(KnowledgeMention(
                entryID: input.id,
                date: input.date,
                mood: normalizedMood(input.mood),
                snippet: snippet(in: text, around: first),
                occurrences: matches.count
            ))
        }
        mentions.sort { lhs, rhs in
            lhs.date != rhs.date ? lhs.date > rhs.date : lhs.entryID.uuidString < rhs.entryID.uuidString
        }

        return KnowledgeMentionSummary(
            mentions: mentions,
            months: monthCounts(for: mentions, now: now, calendar: calendar),
            moods: moodCounts(for: mentions)
        )
    }

    // MARK: Pieces

    private static func mentionExpression(for label: String) -> NSRegularExpression? {
        let escaped = NSRegularExpression.escapedPattern(for: label)
        return try? NSRegularExpression(
            pattern: "(?<![\\p{L}\\p{N}])\(escaped)(?![\\p{L}\\p{N}])",
            options: [.caseInsensitive]
        )
    }

    private static func normalizedMood(_ raw: String?) -> String? {
        let value = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let mood = Mood(rawValue: value), mood != .none else { return nil }
        return mood.rawValue
    }

    /// Months from the first mention (at most `chartMonths` back) to the current month,
    /// or to the last mention when every mention is older than that.
    static func monthCounts(for mentions: [KnowledgeMention], now: Date, calendar: Calendar) -> [KnowledgeMonthCount] {
        guard let newest = mentions.first?.date, let oldest = mentions.last?.date,
              let currentMonth = calendar.dateInterval(of: .month, for: now)?.start,
              let lastMonth = calendar.dateInterval(of: .month, for: newest)?.start,
              let firstMonth = calendar.dateInterval(of: .month, for: oldest)?.start else { return [] }

        let windowStart = calendar.date(byAdding: .month, value: -(chartMonths - 1), to: currentMonth) ?? currentMonth
        let end = lastMonth >= windowStart ? max(currentMonth, lastMonth) : lastMonth
        let earliestShown = calendar.date(byAdding: .month, value: -(chartMonths - 1), to: end) ?? end
        let start = max(firstMonth, earliestShown)

        var counts: [Date: Int] = [:]
        for mention in mentions {
            if let month = calendar.dateInterval(of: .month, for: mention.date)?.start {
                counts[month, default: 0] += 1
            }
        }

        var months: [KnowledgeMonthCount] = []
        var month = start
        while month <= end, months.count < chartMonths {
            months.append(KnowledgeMonthCount(month: month, count: counts[month] ?? 0))
            guard let next = calendar.date(byAdding: .month, value: 1, to: month) else { break }
            month = next
        }
        return months
    }

    private static func moodCounts(for mentions: [KnowledgeMention]) -> [KnowledgeMoodCount] {
        var counts: [Mood: Int] = [:]
        for mention in mentions {
            guard let raw = mention.mood, let mood = Mood(rawValue: raw), mood != .none else { continue }
            counts[mood, default: 0] += 1
        }
        let order = Mood.allCases
        return counts
            .map { KnowledgeMoodCount(mood: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return (order.firstIndex(of: lhs.mood) ?? 0) < (order.firstIndex(of: rhs.mood) ?? 0)
            }
    }

    /// The sentence holding the mention, or a window around it when that sentence is long.
    static func snippet(in text: String, around match: Range<String.Index>) -> String {
        var sentence: Range<String.Index>?
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: [.bySentences, .substringNotRequired]) { _, range, _, stop in
            if range.contains(match.lowerBound) {
                sentence = range
                stop = true
            }
        }
        let candidate = sentence.map { String(text[$0]).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
        if !candidate.isEmpty, candidate.count <= maximumSnippetLength {
            return candidate
        }

        let before = text.index(match.lowerBound, offsetBy: -70, limitedBy: text.startIndex) ?? text.startIndex
        let after = text.index(match.upperBound, offsetBy: 100, limitedBy: text.endIndex) ?? text.endIndex
        var window = String(text[before..<after]).trimmingCharacters(in: .whitespacesAndNewlines)
        if before > text.startIndex { window = "…" + window }
        if after < text.endIndex { window += "…" }
        return window
    }
}
