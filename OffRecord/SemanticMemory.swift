//
//  SemanticMemory.swift
//  OffRecord
//
//  App-side orchestration of the shared SemanticMemoryKit: the index
//  controller bridges Core Data (DiaryEntry) to IndexableEntry values, and
//  EvidenceFridayEngine composes evidence-backed answers. The engines,
//  stores, and search live in the JournalKit package.
//

import Foundation
import NaturalLanguage
import CoreData
import CryptoKit
import os
@_exported import SemanticMemoryKit
@_exported import AssistantCoreKit

private let semanticMemoryLogger = Logger(subsystem: "com.singularity.offrecord", category: "SemanticMemory")

// MARK: - Evidence answer (shared AssistantCoreKit)

typealias EvidenceBackedFridayAnswer = EvidenceBackedAnswer

// MARK: - Core Data bridge

extension IndexableEntry {
    init?(entry: DiaryEntry) {
        guard let id = entry.id else { return nil }
        let text = (entry.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        self.init(
            id: id,
            date: entry.date ?? entry.createdAt ?? Date(),
            mood: entry.value(forKey: "mood") as? String,
            text: text,
            isStarred: entry.isStarred,
            updatedAt: entry.updatedAt
        )
    }
}

/// Historic on-device location of the OffRecord semantic index sidecar.
/// Preserved exactly so existing users do not re-index after the package
/// extraction.
enum OffRecordSemanticIndexLocation {
    static var storeURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base
            .appendingPathComponent("OffRecordIndex", isDirectory: true)
            .appendingPathComponent("semantic-memory.sqlite")
    }
}

// MARK: - Index Controller

@MainActor
final class SemanticMemoryIndexController: ObservableObject {
    static let shared = SemanticMemoryIndexController()

    @Published private(set) var isBuilding = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var statusMessage = String(localized: "Ready", comment: "Search index status: ready to use.")
    @Published private(set) var chunkCount = 0
    @Published private(set) var lastIndexedAt: Date?
    @Published private(set) var usesFallbackEmbeddings = false
    @Published private(set) var lastSearchState: SemanticMemorySearchResult = .ready([])

    private let worker = SemanticMemoryIndexActor(storeURL: OffRecordSemanticIndexLocation.storeURL)
    private var buildTask: Task<Void, Never>?
    private var buildGeneration = 0

    private init() {
        Task { await loadSnapshot() }
    }

    func ensureIndexed(entries: [DiaryEntry]) {
        let records = Self.records(from: entries)
        guard !isBuilding else { return }
        Task {
            if await worker.needsRebuild(records: records) {
                rebuildIndex(records: records)
            }
        }
    }

    func rebuildIndex(entries: [DiaryEntry]) {
        rebuildIndex(records: Self.records(from: entries))
    }

    func upsertEntry(_ entry: DiaryEntry) {
        guard let record = IndexableEntry(entry: entry) else { return }
        upsertRecord(record)
    }

    func upsertRecord(_ record: IndexableEntry) {
        guard !isBuilding else { return }
        Task {
            do {
                let snapshot = try await worker.upsertEntry(record)
                apply(snapshot: snapshot, message: String(localized: "Up to date"))
            } catch {
                semanticMemoryLogger.error("Index update failed: \(error.localizedDescription, privacy: .public)")
                statusMessage = String(localized: "Couldn’t update")
            }
        }
    }

    func deleteEntry(id: UUID?) {
        guard let id, !isBuilding else { return }
        Task {
            do {
                let snapshot = try await worker.deleteEntry(id: id)
                apply(snapshot: snapshot, message: String(localized: "Up to date"))
            } catch {
                semanticMemoryLogger.error("Index entry delete failed: \(error.localizedDescription, privacy: .public)")
                statusMessage = String(localized: "Couldn’t update")
            }
        }
    }

    func deleteIndex() {
        buildGeneration += 1
        buildTask?.cancel()
        buildTask = nil
        isBuilding = false
        progress = 0
        Task {
            do {
                try await worker.deleteAll()
                chunkCount = 0
                lastIndexedAt = nil
                usesFallbackEmbeddings = false
                statusMessage = String(localized: "Deleted", comment: "Search index status: the index was deleted.")
                lastSearchState = .unavailable(String(localized: "Not ready yet"))
            } catch {
                semanticMemoryLogger.error("Index delete failed: \(error.localizedDescription, privacy: .public)")
                statusMessage = String(localized: "Couldn’t update")
            }
        }
    }

    func search(query: String, entries: [DiaryEntry], limit: Int = 18) async -> SemanticMemorySearchResult {
        let records = Self.records(from: entries)
        if isBuilding {
            let state: SemanticMemorySearchResult = .building(progress: progress, message: statusMessage)
            lastSearchState = state
            return state
        }

        if await worker.needsRebuild(records: records) {
            rebuildIndex(records: records)
            let state: SemanticMemorySearchResult = .building(progress: progress, message: statusMessage)
            lastSearchState = state
            return state
        }

        let result = await worker.search(query: query, records: records, limit: limit)
        lastSearchState = result
        return result
    }

    /// Returns once no rebuild is running, or after `timeout`.
    func waitForBuild(timeout: Duration) async {
        let deadline = ContinuousClock.now + timeout
        while isBuilding, ContinuousClock.now < deadline, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(200))
        }
    }

    private func rebuildIndex(records: [IndexableEntry]) {
        buildGeneration += 1
        let generation = buildGeneration
        buildTask?.cancel()
        isBuilding = true
        progress = 0
        statusMessage = String(localized: "Building…")

        buildTask = Task { [weak self] in
            guard let self else { return }
            do {
                let snapshot = try await worker.rebuildAll(records: records) { progress in
                    await MainActor.run {
                        guard generation == self.buildGeneration else { return }
                        self.isBuilding = true
                        self.progress = progress.progress
                        self.statusMessage = progress.message
                    }
                }

                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard generation == self.buildGeneration else { return }
                    self.isBuilding = false
                    self.progress = snapshot.chunks.isEmpty ? 0 : 1
                    self.apply(snapshot: snapshot, message: snapshot.chunks.isEmpty ? String(localized: "No entries yet") : String(localized: "Ready", comment: "Search index status: ready to use."))
                    self.buildTask = nil
                }
            } catch is CancellationError {
                await MainActor.run {
                    guard generation == self.buildGeneration else { return }
                    self.isBuilding = false
                    self.statusMessage = String(localized: "Stopped", comment: "Search index status: the rebuild was cancelled.")
                    self.buildTask = nil
                }
            } catch {
                await MainActor.run {
                    guard generation == self.buildGeneration else { return }
                    semanticMemoryLogger.error("Index build failed: \(error.localizedDescription, privacy: .public)")
                    self.isBuilding = false
                    self.lastSearchState = .failed(String(localized: "Couldn’t update"))
                    self.statusMessage = String(localized: "Couldn’t update")
                    self.buildTask = nil
                }
            }
        }
    }

    private func loadSnapshot() async {
        do {
            if let snapshot = try await worker.load() {
                apply(snapshot: snapshot, message: snapshot.chunks.isEmpty ? String(localized: "Builds on your next search") : String(localized: "Ready", comment: "Search index status: ready to use."))
            } else {
                statusMessage = String(localized: "Builds on your next search")
            }
        } catch {
            semanticMemoryLogger.error("Index load failed: \(error.localizedDescription, privacy: .public)")
            statusMessage = String(localized: "Not available")
            lastSearchState = .failed(String(localized: "Not available"))
        }
    }

    private func apply(snapshot: MemoryIndexSnapshot, message: String) {
        chunkCount = snapshot.chunks.count
        lastIndexedAt = snapshot.updatedAt
        usesFallbackEmbeddings = ProcessInfo.processInfo.arguments.contains("-SemanticMemoryUseFallbackEmbeddings")
            || snapshot.embeddingModelID == UnavailableEmbeddingProvider().metadata.modelID
        statusMessage = usesFallbackEmbeddings && !snapshot.chunks.isEmpty
            ? String(localized: "Ready (basic mode)")
            : message
    }

    private static func records(from entries: [DiaryEntry]) -> [IndexableEntry] {
        entries.compactMap(IndexableEntry.init(entry:))
    }
}

// MARK: - Evidence Friday

@MainActor
enum EvidenceFridayEngine {
    static func answer(question: String, entries: [DiaryEntry], profileSummary: String? = nil) async -> EvidenceBackedFridayAnswer {
        let isSuggestedQuestion = profileSummary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        semanticMemoryLogger.notice(
            "Friday answer requested suggested=\(isSuggestedQuestion.description, privacy: .public) entries=\(entries.count, privacy: .public)"
        )
        let index = SemanticMemoryIndexController.shared
        var searchResult = await index.search(query: question, entries: entries, limit: 6)
        if case .building = searchResult, !isSuggestedQuestion {
            // Asked mid-build, as Ask Friday does at launch: finish reading and answer, rather
            // than replying with a progress note she never follows up on.
            semanticMemoryLogger.notice("Friday waiting for the index build before answering.")
            await index.waitForBuild(timeout: .seconds(20))
            searchResult = await index.search(query: question, entries: entries, limit: 6)
        }

        switch searchResult {
        case .building(let progress, _):
            if let fallback = profileFallbackAnswer(
                profileSummary: profileSummary,
                limitation: String(localized: "I can’t point to specific entries right now.")
            ) {
                semanticMemoryLogger.notice("Friday using suggested profile fallback while index is building.")
                return fallback
            }
            return EvidenceBackedFridayAnswer(
                summary: String(localized: "I’m still reading your journal."),
                observations: [EvidenceObservation(text: String(localized: "\(Int(progress * 100))% done."), evidenceIDs: [])],
                evidence: [],
                confidence: 0,
                followUpPrompt: nil,
                limitations: String(localized: "I’ll answer once I’ve read everything.")
            )
        case .unavailable(let reason):
            semanticMemoryLogger.notice("Friday search unavailable: \(reason, privacy: .public)")
            if let fallback = profileFallbackAnswer(
                profileSummary: profileSummary,
                limitation: String(localized: "I can’t point to specific entries right now.")
            ) {
                semanticMemoryLogger.notice("Friday using suggested profile fallback because search is unavailable.")
                return fallback
            }
            return EvidenceBackedFridayAnswer(
                summary: String(localized: "I do not have enough journal evidence to answer that yet."),
                observations: [],
                evidence: [],
                confidence: 0,
                followUpPrompt: nil,
                limitations: String(localized: "I only answer from your entries.")
            )
        case .failed(let message):
            semanticMemoryLogger.error("Friday search failed: \(message, privacy: .public)")
            if let fallback = profileFallbackAnswer(
                profileSummary: profileSummary,
                limitation: String(localized: "I can’t point to specific entries right now.")
            ) {
                semanticMemoryLogger.notice("Friday using suggested profile fallback because search failed.")
                return fallback
            }
            return EvidenceBackedFridayAnswer(
                summary: String(localized: "I couldn’t search your journal just now."),
                observations: [EvidenceObservation(text: String(localized: "Try again in a moment."), evidenceIDs: [])],
                evidence: [],
                confidence: 0,
                followUpPrompt: nil,
                limitations: nil
            )
        case .ready(let evidence):
            return await answer(question: question, evidence: evidence, profileSummary: profileSummary)
        }
    }

    static func answer(question: String, evidence: [EvidenceReference], profileSummary: String? = nil) async -> EvidenceBackedFridayAnswer {
        let strongEvidence = strongEvidence(from: evidence)
        semanticMemoryLogger.notice(
            "Friday evidence evaluated retrieved=\(evidence.count, privacy: .public) strong=\(strongEvidence.count, privacy: .public) profileFallback=\((profileSummary?.isEmpty == false).description, privacy: .public)"
        )

        guard !strongEvidence.isEmpty else {
            if let fallback = profileFallbackAnswer(
                profileSummary: profileSummary,
                limitation: String(localized: "I couldn’t find supporting entries for this.")
            ) {
                semanticMemoryLogger.notice("Friday using suggested profile fallback because evidence was weak.")
                return fallback
            }
            return EvidenceBackedFridayAnswer(
                summary: String(localized: "I do not have enough journal evidence to answer that yet."),
                observations: [EvidenceObservation(text: String(localized: "Try asking about a person, topic, mood, or time you’ve written about."), evidenceIDs: [])],
                evidence: [],
                confidence: 0,
                followUpPrompt: nil,
                limitations: String(localized: "I only answer from journal evidence I can find.")
            )
        }

        let topEvidence = Array(strongEvidence.prefix(4))
        let summary = profileSummary?.isEmpty == false ? profileSummary! : buildSummary(question: question, evidence: topEvidence)
        let observations = buildObservations(question: question, evidence: topEvidence)
        let confidence = min(0.9, 0.35 + Double(topEvidence.count) * 0.11 + (topEvidence.first?.score ?? 0) * 5)

        let deterministicAnswer = EvidenceBackedFridayAnswer(
            summary: summary,
            observations: observations,
            evidence: topEvidence,
            confidence: confidence,
            followUpPrompt: nil,
            limitations: confidence < 0.65 ? String(localized: "I’m not sure. Only a few entries match.") : nil
        )

        #if canImport(FoundationModels)
        if profileSummary == nil {
            if #available(iOS 26.0, *),
               let generatedAnswer = try? await FoundationModelsFridayResponder.answer(
                question: question,
                evidence: topEvidence,
                fallback: deterministicAnswer
               ) {
                return generatedAnswer
            }
        }
        #endif

        return deterministicAnswer
    }

    private static func strongEvidence(from evidence: [EvidenceReference]) -> [EvidenceReference] {
        guard let top = evidence.first else { return [] }
        let hasLexicalSupport = evidence.contains { $0.matchReason == .exact || $0.matchReason == .entity }
        let hasMultipleMatches = evidence.count >= 2 && (evidence.dropFirst().first?.score ?? 0) >= 0.014

        if SemanticMemoryIndexController.shared.usesFallbackEmbeddings && !hasLexicalSupport {
            semanticMemoryLogger.notice("Rejecting fallback evidence because lexical support is missing.")
            return []
        }

        if hasLexicalSupport {
            return evidence.filter { $0.score >= 0.012 }
        }
        if top.score >= 0.024 || hasMultipleMatches {
            return evidence.filter { $0.score >= 0.014 }
        }
        return []
    }

    private static func profileFallbackAnswer(profileSummary: String?, limitation: String) -> EvidenceBackedFridayAnswer? {
        guard let profileSummary = profileSummary?.trimmingCharacters(in: .whitespacesAndNewlines),
              !profileSummary.isEmpty else { return nil }
        return EvidenceBackedFridayAnswer(
            summary: profileSummary,
            observations: [],
            evidence: [],
            confidence: 0.45,
            followUpPrompt: nil,
            limitations: limitation
        )
    }

    private static func buildSummary(question: String, evidence: [EvidenceReference]) -> String {
        let topic = TextSignals.tokens(in: question).prefix(3).joined(separator: " ")
        let dates = evidence.map { $0.date }.sorted()
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        let dateText: String
        if let first = dates.first, let last = dates.last, !Calendar.current.isDate(first, inSameDayAs: last) {
            dateText = String(localized: "\(formatter.string(from: first)) to \(formatter.string(from: last))", comment: "A date range, from the first date to the last.")
        } else if let first = dates.first {
            dateText = formatter.string(from: first)
        } else {
            dateText = String(localized: "your journal", comment: "Used in place of a date range, as in “3 entries from your journal mention this.”")
        }

        let entryCount = String(AttributedString(localized: "^[\(evidence.count) entry](inflect: true)").characters)
        if topic.isEmpty {
            return evidence.count == 1
                ? String(localized: "\(entryCount) from \(dateText) mentions this.", comment: "The first argument is “1 entry”; the second is a date, a date range, or “your journal”.")
                : String(localized: "\(entryCount) from \(dateText) mention this.", comment: "The first argument is a count like “3 entries”; the second is a date, a date range, or “your journal”.")
        }
        return evidence.count == 1
            ? String(localized: "\(entryCount) from \(dateText) mentions \(topic).", comment: "The first argument is “1 entry”; the second is a date, a date range, or “your journal”; the third is the words asked about.")
            : String(localized: "\(entryCount) from \(dateText) mention \(topic).", comment: "The first argument is a count like “3 entries”; the second is a date, a date range, or “your journal”; the third is the words asked about.")
    }

    private static func buildObservations(question: String, evidence: [EvidenceReference]) -> [EvidenceObservation] {
        let queryTokens = TextSignals.expandedTokens(in: question)
        let topicCounts = Dictionary(grouping: evidence.flatMap { TextSignals.tokens(in: $0.chunkText) }, by: { $0 }).mapValues(\.count)
        let recurring = topicCounts
            .filter { !TextSignals.stopWords.contains($0.key) && queryTokens.contains($0.key) }
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map(\.key)

        var observations: [EvidenceObservation] = []
        let allEvidenceIDs = evidence.map(\.id)
        if !recurring.isEmpty {
            observations.append(EvidenceObservation(text: String(localized: "Words that come up most: \(recurring.joined(separator: ", ")).", comment: "The argument is a comma-separated list of words."), evidenceIDs: allEvidenceIDs))
        }

        let moods = evidence.compactMap(\.mood).filter { !$0.isEmpty }
        if let mood = Dictionary(grouping: moods, by: { $0 }).max(by: { $0.value.count < $1.value.count })?.key {
            let moodEvidenceIDs = evidence.filter { $0.mood == mood }.map(\.id)
            observations.append(EvidenceObservation(text: String(localized: "Most were tagged \(Mood(rawValue: mood)?.displayName ?? mood.capitalized).", comment: "The argument is a mood name."), evidenceIDs: moodEvidenceIDs))
        }

        if let first = evidence.first {
            observations.append(EvidenceObservation(text: String(localized: "The clearest example: “\(first.snippet)”", comment: "The argument is a quote from one of the person’s entries."), evidenceIDs: [first.id]))
        }
        return observations
    }
}
