//
//  FridayConversationTools.swift
//  OffRecord
//
//  The three journal tools Friday's chat model may call, written as plain
//  functions so they run (and are tested) without a model:
//
//  - searchJournal: the search index, minus high-risk passages and entries
//    kept out of Friday.
//  - moodStats: how moods were tagged over a date range. Counts and dates
//    only; no entry text reaches the model.
//  - person: what Friday remembers about a name, honoring Forget and Rename,
//    plus the entries that mention it.
//
//  Every evidence item a tool hands the model is recorded in the ledger. The
//  final answer may cite only those IDs.
//

import Foundation
import JournalFoundation
import KnowledgeGraphKit
import SemanticMemoryKit

// MARK: - Ledger

/// What the tools returned in this conversation, and whether the current turn
/// hit high-risk content. Tools run concurrently off the main actor, so access
/// is locked.
final class FridayToolLedger: @unchecked Sendable {
    private let lock = NSLock()
    private var evidenceByID: [String: EvidenceReference] = [:]
    private var evidenceOrder: [String] = []
    private var turnWithheldHighRisk = false
    private var turnToolCalls: [String] = []

    /// Starts a turn: clears the per-turn flags, keeps evidence the model already saw.
    func beginTurn() {
        lock.withLock {
            turnWithheldHighRisk = false
            turnToolCalls = []
        }
    }

    /// Forgets everything, as when the model's transcript drops old tool output.
    func reset() {
        lock.withLock {
            evidenceByID = [:]
            evidenceOrder = []
            turnWithheldHighRisk = false
            turnToolCalls = []
        }
    }

    func recordCall(_ tool: String) {
        lock.withLock { turnToolCalls.append(tool) }
    }

    func record(_ references: [EvidenceReference]) {
        lock.withLock {
            for reference in references where evidenceByID[reference.id] == nil {
                evidenceByID[reference.id] = reference
                evidenceOrder.append(reference.id)
            }
        }
    }

    func markWithheldHighRisk() {
        lock.withLock { turnWithheldHighRisk = true }
    }

    var withheldHighRisk: Bool { lock.withLock { turnWithheldHighRisk } }
    var toolCalls: [String] { lock.withLock { turnToolCalls } }
    var evidenceIDs: Set<String> { lock.withLock { Set(evidenceByID.keys) } }

    func evidence(for ids: [String]) -> [EvidenceReference] {
        lock.withLock { ids.compactMap { evidenceByID[$0] } }
    }
}

// MARK: - Context

/// A Sendable snapshot of what the tools may read, taken on the main actor at
/// the start of each turn.
struct FridayJournalToolContext: Sendable {
    typealias Search = @Sendable (String) async -> SemanticMemorySearchResult
    typealias StrongFilter = @Sendable ([EvidenceReference]) async -> [EvidenceReference]

    /// Entries Friday may use (already filtered for "Keep out of Friday").
    let records: [IndexableEntry]
    let graph: PersonalKnowledgeGraph
    let forgottenIDs: Set<String>
    let aliases: [String: String]
    let now: Date
    let calendar: Calendar
    let search: Search
    let strongEvidence: StrongFilter

    var permittedEntryIDs: Set<UUID> { Set(records.map(\.id)) }
}

// MARK: - Tools

enum FridayJournalTools {
    static let searchToolName = "searchJournal"
    static let moodToolName = "moodStats"
    static let personToolName = "person"
    static let maximumResults = 5

    private static let noResults = "No matching entries."

    // MARK: searchJournal

    static func searchJournal(query: String, context: FridayJournalToolContext, ledger: FridayToolLedger) async -> String {
        ledger.recordCall(searchToolName)
        let evidence = await safeEvidence(for: query, context: context, ledger: ledger)
        guard let evidence else { return noResults }
        ledger.record(evidence)
        return evidence.map(describe).joined(separator: "\n")
    }

    /// Strong, permitted, non-high-risk matches for `query`; nil when there are none
    /// or when the strongest matches were all high-risk (the ledger is flagged then).
    static func safeEvidence(for query: String, context: FridayJournalToolContext, ledger: FridayToolLedger) async -> [EvidenceReference]? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // A search for self-harm is never run; the turn ends in support copy.
        if JournalRiskClassifier.level(for: trimmed) == .highRiskExcluded {
            ledger.markWithheldHighRisk()
            return nil
        }
        guard case .ready(let results) = await context.search(trimmed) else { return nil }

        let permittedIDs = context.permittedEntryIDs
        let permitted = results.filter { permittedIDs.contains($0.entryID) }
        let isHighRisk: @Sendable (EvidenceReference) -> Bool = { JournalRiskClassifier.level(for: $0.chunkText) == .highRiskExcluded }
        let safe = permitted.filter { !isHighRisk($0) }
        if safe.count < permitted.count {
            // Same rule as the deterministic answer: if every strong match is high-risk, support only.
            let strongRetrieved = await context.strongEvidence(permitted)
            if !strongRetrieved.isEmpty, strongRetrieved.allSatisfy(isHighRisk) {
                ledger.markWithheldHighRisk()
                return nil
            }
        }
        let strong = Array(await context.strongEvidence(safe).prefix(maximumResults))
        return strong.isEmpty ? nil : strong
    }

    // MARK: moodStats

    /// Mood counts between two dates (yyyy-MM-dd). Defaults to the last 30 days.
    static func moodStats(startDate: String?, endDate: String?, context: FridayJournalToolContext, ledger: FridayToolLedger) -> String {
        ledger.recordCall(moodToolName)
        let calendar = context.calendar
        let today = calendar.startOfDay(for: context.now)
        var end = parseDay(endDate, calendar: calendar).map { min($0, today) } ?? today
        var start = parseDay(startDate, calendar: calendar) ?? calendar.date(byAdding: .day, value: -29, to: end) ?? end
        if start > end { swap(&start, &end) }
        let endOfRange = calendar.date(byAdding: .day, value: 1, to: end) ?? end

        // High-risk entries aren't analyzed, counted, or cited.
        let inRange = context.records
            .filter { $0.date >= start && $0.date < endOfRange }
            .filter { JournalRiskClassifier.level(for: $0.text) != .highRiskExcluded }
            .sorted { $0.date > $1.date }
        let range = "\(dayString(start, calendar: calendar)) to \(dayString(end, calendar: calendar))"
        guard !inRange.isEmpty else { return "No entries from \(range)." }

        let tagged = inRange.filter { !($0.mood ?? "").isEmpty }
        var lines = ["\(inRange.count) entries from \(range); \(tagged.count) have a mood."]
        let groups = Dictionary(grouping: tagged, by: { $0.mood ?? "" })
        let ordered = groups.sorted {
            if $0.value.count != $1.value.count { return $0.value.count > $1.value.count }
            return $0.key < $1.key
        }
        var cited: [EvidenceReference] = []
        for (mood, entries) in ordered {
            let examples = entries.prefix(2).map { reference(for: $0) }
            cited += examples
            let name = Mood(rawValue: mood)?.displayName.lowercased() ?? mood
            lines.append("\(name): \(entries.count) (ids: \(examples.map(\.id).joined(separator: ", ")))")
        }
        ledger.record(cited)
        return lines.joined(separator: "\n")
    }

    // MARK: person

    /// What Friday remembers about `name`, and the entries that mention it.
    static func person(name: String, context: FridayJournalToolContext, ledger: FridayToolLedger) async -> String {
        ledger.recordCall(personToolName)
        let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !wanted.isEmpty, let node = node(named: wanted, in: context) else {
            return "Nothing remembered about \(name)."
        }
        let display = displayName(for: node, context: context)
        let tone: String
        if node.sentimentAssociation > 0.2 {
            tone = "usually upbeat"
        } else if node.sentimentAssociation < -0.2 {
            tone = "usually heavier"
        } else {
            tone = "mixed"
        }
        let related = context.graph.connections(for: node.id)
            .map(\.node)
            .filter { !context.forgottenIDs.contains($0.id) }
            .sorted { $0.importance > $1.importance }
            .prefix(4)
            .map { displayName(for: $0, context: context) }
        var lines = [
            "\(display) (\(node.type.rawValue)): mentioned \(node.mentions) times, from \(dayString(node.firstSeen, calendar: context.calendar)) to \(dayString(node.lastSeen, calendar: context.calendar)). Entries about them are \(tone).",
        ]
        if !related.isEmpty {
            lines.append("Often mentioned with: \(related.joined(separator: ", ")).")
        }
        // Search by the name as written in entries, not the rename.
        if let evidence = await safeEvidence(for: node.label, context: context, ledger: ledger) {
            ledger.record(evidence)
            lines.append("Entries:")
            lines += evidence.map(describe)
        }
        return lines.joined(separator: "\n")
    }

    /// The remembered node for a name or its rename; forgotten ones don't exist.
    static func node(named lowercasedName: String, in context: FridayJournalToolContext) -> PersonalKnowledgeGraph.KnowledgeNode? {
        let candidates = context.graph.nodes.values.filter { node in
            guard !context.forgottenIDs.contains(node.id) else { return false }
            if node.id == lowercasedName || node.label.lowercased() == lowercasedName { return true }
            return context.aliases[node.id]?.lowercased() == lowercasedName
        }
        return candidates.sorted {
            if ($0.type == .person) != ($1.type == .person) { return $0.type == .person }
            return $0.importance > $1.importance
        }.first
    }

    static func displayName(for node: PersonalKnowledgeGraph.KnowledgeNode, context: FridayJournalToolContext) -> String {
        if let alias = context.aliases[node.id], !alias.isEmpty { return alias }
        return node.label
    }

    // MARK: Formatting

    static func describe(_ reference: EvidenceReference) -> String {
        let mood = (reference.mood ?? "").isEmpty ? "none" : (Mood(rawValue: reference.mood ?? "")?.displayName.lowercased() ?? reference.mood ?? "none")
        return "id: \(reference.id); date: \(reference.date.formatted(date: .abbreviated, time: .omitted)); mood: \(mood); excerpt: \(reference.snippet)"
    }

    /// An entry as evidence for mood counts. The model sees only its ID; the
    /// excerpt is for the citation chip.
    static func reference(for record: IndexableEntry) -> EvidenceReference {
        EvidenceReference(
            id: "mood-\(record.id.uuidString)",
            entryID: record.id,
            date: record.date,
            mood: record.mood,
            snippet: TextSignals.snippet(from: record.text, query: ""),
            chunkText: record.text,
            score: 0.02,
            matchReason: .recent
        )
    }

    static func parseDay(_ value: String?, calendar: Calendar) -> Date? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    static func dayString(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}
