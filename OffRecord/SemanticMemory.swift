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
    @Published private(set) var statusMessage = "Semantic memory is ready."
    @Published private(set) var chunkCount = 0
    @Published private(set) var lastIndexedAt: Date?
    @Published private(set) var usesFallbackEmbeddings = false
    @Published private(set) var lastSearchState: SemanticMemorySearchResult = .ready([])

    private let worker = SemanticMemoryIndexActor(storeURL: OffRecordSemanticIndexLocation.storeURL)
    private var buildTask: Task<Void, Never>?
    private var buildGeneration = 0
    private var needsRemoteReconcile = false

    private init() {
        Task { await loadSnapshot() }
    }

    func markNeedsReconcile() {
        needsRemoteReconcile = true
        statusMessage = "Semantic memory will reconcile synced changes soon."
    }

    func ensureIndexed(entries: [DiaryEntry]) {
        let records = Self.records(from: entries)
        guard !isBuilding else { return }
        Task {
            let needsRebuild = await worker.needsRebuild(records: records, forceRemoteReconcile: needsRemoteReconcile)
            if needsRebuild {
                rebuildIndex(records: records)
            }
        }
    }

    func rebuildIndex(entries: [DiaryEntry]) {
        rebuildIndex(records: Self.records(from: entries))
    }

    func reconcileRemoteChanges(entries: [DiaryEntry]) {
        needsRemoteReconcile = true
        ensureIndexed(entries: entries)
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
                apply(snapshot: snapshot, message: "Semantic memory updated.")
            } catch {
                statusMessage = "Semantic memory update failed: \(error.localizedDescription)"
            }
        }
    }

    func deleteEntry(id: UUID?) {
        guard let id, !isBuilding else { return }
        Task {
            do {
                let snapshot = try await worker.deleteEntry(id: id)
                apply(snapshot: snapshot, message: "Semantic memory updated.")
            } catch {
                statusMessage = "Semantic memory update failed: \(error.localizedDescription)"
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
                statusMessage = "Semantic memory index deleted. Rebuild anytime."
                lastSearchState = .unavailable("Semantic memory index deleted. Rebuild anytime.")
            } catch {
                statusMessage = "Semantic memory delete failed: \(error.localizedDescription)"
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

        let needsRebuild = await worker.needsRebuild(records: records, forceRemoteReconcile: needsRemoteReconcile)
        if needsRebuild {
            rebuildIndex(records: records)
            let state: SemanticMemorySearchResult = .building(progress: progress, message: statusMessage)
            lastSearchState = state
            return state
        }

        let result = await worker.search(query: query, records: records, limit: limit)
        lastSearchState = result
        return result
    }

    private func rebuildIndex(records: [IndexableEntry]) {
        buildGeneration += 1
        let generation = buildGeneration
        buildTask?.cancel()
        isBuilding = true
        progress = 0
        statusMessage = "Building semantic memory..."

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
                    self.needsRemoteReconcile = false
                    self.isBuilding = false
                    self.progress = snapshot.chunks.isEmpty ? 0 : 1
                    self.apply(snapshot: snapshot, message: snapshot.chunks.isEmpty ? "Semantic memory has no entries to index." : "Semantic memory is ready.")
                    self.buildTask = nil
                }
            } catch is CancellationError {
                await MainActor.run {
                    guard generation == self.buildGeneration else { return }
                    self.isBuilding = false
                    self.statusMessage = "Semantic memory build cancelled."
                    self.buildTask = nil
                }
            } catch {
                await MainActor.run {
                    guard generation == self.buildGeneration else { return }
                    self.isBuilding = false
                    self.lastSearchState = .failed(error.localizedDescription)
                    self.statusMessage = "Semantic memory build failed: \(error.localizedDescription)"
                    self.buildTask = nil
                }
            }
        }
    }

    private func loadSnapshot() async {
        do {
            if let snapshot = try await worker.load() {
                apply(snapshot: snapshot, message: snapshot.chunks.isEmpty ? "Semantic memory will build after your next search." : "Semantic memory is ready.")
            } else {
                statusMessage = "Semantic memory will build after your next search."
            }
        } catch {
            statusMessage = "Semantic memory unavailable: \(error.localizedDescription)"
            lastSearchState = .failed(error.localizedDescription)
        }
    }

    private func apply(snapshot: MemoryIndexSnapshot, message: String) {
        chunkCount = snapshot.chunks.count
        lastIndexedAt = snapshot.updatedAt
        usesFallbackEmbeddings = ProcessInfo.processInfo.arguments.contains("-SemanticMemoryUseFallbackEmbeddings")
            || snapshot.embeddingModelID == UnavailableEmbeddingProvider().metadata.modelID
        statusMessage = usesFallbackEmbeddings && !snapshot.chunks.isEmpty
            ? "Semantic memory is ready with lexical fallback. Sentence embeddings were unavailable for this index."
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
        let searchResult = await SemanticMemoryIndexController.shared.search(query: question, entries: entries, limit: 6)

        switch searchResult {
        case .building(let progress, let message):
            if let fallback = profileFallbackAnswer(
                profileSummary: profileSummary,
                limitation: "Semantic Memory is still indexing, so citations are not attached yet."
            ) {
                semanticMemoryLogger.notice("Friday using suggested profile fallback while index is building.")
                return fallback
            }
            return EvidenceBackedFridayAnswer(
                summary: "Friday is still building semantic memory.",
                observations: [EvidenceObservation(text: "\(message) \(Int(progress * 100))% complete.", evidenceIDs: [])],
                evidence: [],
                confidence: 0,
                followUpPrompt: "Try again when indexing finishes.",
                limitations: "Friday will not answer from a partially built index."
            )
        case .unavailable(let reason):
            if let fallback = profileFallbackAnswer(
                profileSummary: profileSummary,
                limitation: "Semantic Memory is unavailable right now, so citations are not attached. \(reason)"
            ) {
                semanticMemoryLogger.notice("Friday using suggested profile fallback because search is unavailable.")
                return fallback
            }
            return EvidenceBackedFridayAnswer(
                summary: "I do not have enough journal evidence to answer that yet.",
                observations: [EvidenceObservation(text: reason, evidenceIDs: [])],
                evidence: [],
                confidence: 0,
                followUpPrompt: "What part of this do you want to start tracking?",
                limitations: "Friday only answers from entries stored on this device."
            )
        case .failed(let message):
            if let fallback = profileFallbackAnswer(
                profileSummary: profileSummary,
                limitation: "Semantic Memory search failed, so citations are not attached. \(message)"
            ) {
                semanticMemoryLogger.notice("Friday using suggested profile fallback because search failed.")
                return fallback
            }
            return EvidenceBackedFridayAnswer(
                summary: "Friday could not search your journal right now.",
                observations: [EvidenceObservation(text: message, evidenceIDs: [])],
                evidence: [],
                confidence: 0,
                followUpPrompt: "Try rebuilding Semantic Memory in Settings.",
                limitations: "No claims were generated because retrieval failed."
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
                limitation: "Semantic Memory could not find supporting entries for citations."
            ) {
                semanticMemoryLogger.notice("Friday using suggested profile fallback because evidence was weak.")
                return fallback
            }
            return EvidenceBackedFridayAnswer(
                summary: "I do not have enough journal evidence to answer that yet.",
                observations: [EvidenceObservation(text: "Try asking after a few more entries, or search for a person, topic, mood, or time period you have written about.", evidenceIDs: [])],
                evidence: [],
                confidence: 0,
                followUpPrompt: "What part of this do you want to start tracking?",
                limitations: "Friday only answers from retrieved journal evidence."
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
            followUpPrompt: "Do you want to open one of these entries and reflect on it?",
            limitations: confidence < 0.65 ? "This is a low-confidence answer based on a small set of matching entries." : nil
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
            followUpPrompt: "Ask about a specific person, topic, mood, or time period if you want citations.",
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
            dateText = "\(formatter.string(from: first)) to \(formatter.string(from: last))"
        } else if let first = dates.first {
            dateText = formatter.string(from: first)
        } else {
            dateText = "your recent entries"
        }

        if topic.isEmpty {
            return "I found \(evidence.count) relevant journal memories from \(dateText)."
        }
        return "I found \(evidence.count) journal memories related to \(topic) from \(dateText)."
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
            observations.append(EvidenceObservation(text: "The strongest recurring terms are \(recurring.joined(separator: ", ")).", evidenceIDs: allEvidenceIDs))
        }

        let moods = evidence.compactMap(\.mood).filter { !$0.isEmpty }
        if let mood = Dictionary(grouping: moods, by: { $0 }).max(by: { $0.value.count < $1.value.count })?.key {
            let moodEvidenceIDs = evidence.filter { $0.mood == mood }.map(\.id)
            observations.append(EvidenceObservation(text: "The matching entries most often carry a \(mood) mood.", evidenceIDs: moodEvidenceIDs))
        }

        if let first = evidence.first {
            observations.append(EvidenceObservation(text: "The clearest supporting memory is: \"\(first.snippet)\"", evidenceIDs: [first.id]))
        }

        if observations.isEmpty {
            observations.append(EvidenceObservation(text: "The answer is grounded in the cited entries below.", evidenceIDs: allEvidenceIDs))
        }
        return observations
    }
}
