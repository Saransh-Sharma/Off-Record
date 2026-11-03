//
//  AskFridaySiri.swift
//  OffRecord
//
//  What Ask Friday says inside Siri, decided apart from App Intents so it
//  can be tested without Siri.
//
//  - A high-risk question never reaches retrieval: Siri says Friday's
//    support line and the app opens to the Get Support sheet.
//  - Otherwise Siri gives the answer's summary only: no evidence, no
//    snippets, no quotes. A summary that quotes, repeats a run of words from
//    an entry, or speaks in the first person (Siri is neutral chrome) is
//    replaced by a count and date range built from entry metadata.
//  - With Friday turned off in Settings there is no answer.
//  - Retrieval can wait on a search-index build, so the answer has a time
//    limit; past it, Siri offers to open Friday instead.
//

import CoreData
import Foundation
import JournalFoundation
import SemanticMemoryKit

enum AskFridaySiriReply: Equatable, Sendable {
    case needsQuestion
    /// Friday's support line; the app opens to Get Support.
    case support(String)
    case fridayOff
    /// The spoken and shown answer, offered with Open in Friday.
    case answer(String)
    /// The answer took too long; Siri offers Open in Friday.
    case needsMoreTime
}

enum AskFridaySiri {
    /// How long Siri waits for Friday before offering to open the app.
    static let answerTimeout: Duration = .seconds(8)
    /// Words in a row shared with an entry that make a summary a quote.
    static let quotedRunLength = 5

    static var isFridayEnabled: Bool {
        FridayAvailability.isEnabled
    }

    static func reply(
        to question: String?,
        fridayEnabled: Bool,
        timeout: Duration = answerTimeout,
        answer: @escaping @Sendable (String) async -> EvidenceBackedFridayAnswer
    ) async -> AskFridaySiriReply {
        let question = question?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !question.isEmpty else { return .needsQuestion }

        // Safety comes first, even with Friday off: support copy, never analysis.
        if JournalRiskClassifier.responseMode(for: question) == .supportOnly {
            return .support(FridayPersonality.riskSafeSupport)
        }
        guard fridayEnabled else { return .fridayOff }

        guard let result = await firstResult(within: timeout, { await answer(question) }) else {
            return .needsMoreTime
        }
        if result.responseMode == .supportOnly || JournalRiskClassifier.level(for: result.summary) == .highRiskExcluded {
            return .support(FridayPersonality.riskSafeSupport)
        }
        return .answer(spokenSummary(for: result))
    }

    // MARK: Summary

    /// Friday's summary when Siri can say it; otherwise a count of matching entries.
    static func spokenSummary(for answer: EvidenceBackedFridayAnswer) -> String {
        let summary = answer.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let entryTexts = answer.evidence.flatMap { [$0.chunkText, $0.snippet] }
        if isSafeToSpeak(summary, entryTexts: entryTexts) {
            return summary
        }
        return metadataSummary(for: answer.evidence)
    }

    static func isSafeToSpeak(_ summary: String, entryTexts: [String]) -> Bool {
        guard !summary.isEmpty else { return false }
        return !containsQuotation(summary)
            && !speaksInFirstPerson(summary)
            && !sharesWordRun(summary, with: entryTexts, length: quotedRunLength)
    }

    /// "3 entries from May 2 to May 9 match." Built from dates and counts only.
    static func metadataSummary(for evidence: [EvidenceReference]) -> String {
        let entryCount = Set(evidence.map(\.entryID)).count
        guard entryCount > 0 else {
            return String(localized: "No entries match that yet.")
        }
        let dates = evidence.map(\.date).sorted()
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        let count = String(AttributedString(localized: "^[\(entryCount) entry](inflect: true)").characters)
        if let first = dates.first, let last = dates.last, !Calendar.current.isDate(first, inSameDayAs: last) {
            return String(
                localized: "\(count) from \(formatter.string(from: first)) to \(formatter.string(from: last)) match.",
                comment: "Siri answer built from dates only, e.g. “3 entries from May 2 to May 9 match.”"
            )
        }
        let day = dates.first.map(formatter.string(from:)) ?? ""
        return entryCount == 1
            ? String(localized: "\(count) from \(day) matches.", comment: "Siri answer built from dates only, e.g. “1 entry from May 2 matches.”")
            : String(localized: "\(count) from \(day) match.", comment: "Siri answer built from dates only, e.g. “2 entries from May 2 match.”")
    }

    static func containsQuotation(_ text: String) -> Bool {
        text.contains { "\"“”«»„".contains($0) }
    }

    static func speaksInFirstPerson(_ text: String) -> Bool {
        let firstPerson: Set<String> = ["i", "i’m", "i'm", "i’ve", "i've", "i’ll", "i'll", "i’d", "i'd", "me", "my", "mine", "myself"]
        return words(in: text, keepingApostrophes: true).contains { firstPerson.contains($0) }
    }

    /// Whether `text` repeats `length` or more words in a row from any of `sources`.
    static func sharesWordRun(_ text: String, with sources: [String], length: Int) -> Bool {
        let textWords = words(in: text)
        guard length > 0, textWords.count >= length else { return false }
        let runs = Set((0...(textWords.count - length)).map { textWords[$0..<($0 + length)].joined(separator: " ") })
        return sources.contains { source in
            let sourceWords = words(in: source)
            guard sourceWords.count >= length else { return false }
            return (0...(sourceWords.count - length)).contains { runs.contains(sourceWords[$0..<($0 + length)].joined(separator: " ")) }
        }
    }

    private static func words(in text: String, keepingApostrophes: Bool = false) -> [String] {
        text.lowercased()
            .split { character in
                if keepingApostrophes, character == "'" || character == "’" { return false }
                return !(character.isLetter || character.isNumber)
            }
            .map(String.init)
    }

    // MARK: Time limit

    /// The operation's result, or nil if `timeout` passes first. The operation keeps
    /// running after a timeout and its result is dropped, so a slow index build
    /// can't hold Siri past its budget.
    static func firstResult<Value: Sendable>(
        within timeout: Duration,
        _ operation: @escaping @Sendable () async -> Value
    ) async -> Value? {
        await withCheckedContinuation { continuation in
            let gate = ResumeOnce(continuation)
            Task { gate.resume(with: await operation()) }
            Task {
                try? await Task.sleep(for: timeout)
                gate.resume(with: nil)
            }
        }
    }

    // MARK: Journal

    /// Started entries, newest first. "Keep Out of Friday" filtering happens in the engine.
    @MainActor
    static func journalEntries() -> [DiaryEntry] {
        let request: NSFetchRequest<DiaryEntry> = DiaryEntry.fetchRequest()
        request.predicate = DiaryEntry.startedEntryPredicate
        request.sortDescriptors = [NSSortDescriptor(keyPath: \DiaryEntry.date, ascending: false)]
        let entries = (try? PersistenceController.shared.container.viewContext.fetch(request)) ?? []
        return entries.startedEntries
    }
}

/// Resumes a continuation with the first value it gets and ignores the rest.
private final class ResumeOnce<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value?, Never>?

    init(_ continuation: CheckedContinuation<Value?, Never>) {
        self.continuation = continuation
    }

    func resume(with value: Value?) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}
