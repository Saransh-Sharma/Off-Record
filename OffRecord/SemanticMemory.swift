//
//  SemanticMemory.swift
//  OffRecord
//
//  Local-only semantic memory index for evidence-backed search and Friday answers.
//  Derived embeddings never sync; each device can rebuild them from journal entries.
//

import Foundation
import NaturalLanguage
import CoreData
import CryptoKit
import SQLite3
#if canImport(Accelerate)
import Accelerate
#endif

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Evidence Model

struct EvidenceReference: Identifiable, Codable, Equatable, Sendable {
    enum MatchReason: String, Codable, Sendable {
        case meaning = "Meaning match"
        case exact = "Exact match"
        case entity = "Person or topic match"
        case recent = "Recent related entry"
    }

    let id: String
    let entryID: UUID
    let date: Date
    let mood: String?
    let snippet: String
    let chunkText: String
    let score: Double
    let matchReason: MatchReason
}

struct EvidenceObservation: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let text: String
    let evidenceIDs: [String]

    init(text: String, evidenceIDs: [String]) {
        self.id = TextSignals.hash(text + evidenceIDs.joined()).prefix(16).description
        self.text = text
        self.evidenceIDs = evidenceIDs
    }
}

struct EvidenceBackedFridayAnswer: Identifiable, Equatable, Sendable {
    let id = UUID()
    let summary: String
    let observations: [EvidenceObservation]
    let evidence: [EvidenceReference]
    let confidence: Double
    let followUpPrompt: String?
    let limitations: String?
}

enum SemanticMemorySearchResult: Equatable, Sendable {
    case ready([EvidenceReference])
    case building(progress: Double, message: String)
    case unavailable(String)
    case failed(String)
}

private struct IndexProgress: Sendable {
    let progress: Double
    let message: String
}

// MARK: - Stored Index

struct MemoryChunk: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let entryID: UUID
    let chunkIndex: Int
    let date: Date
    let mood: String?
    let textHash: String
    let entryTextHash: String
    let characterStart: Int
    let characterEnd: Int
    let entities: [String]
    let topics: [String]
    let embeddingModelID: String
    let embeddingRevision: Int
    let embeddingDimension: Int
    let language: String
    let vector: [Float]
    let isStarred: Bool
}

struct MemoryIndexSnapshot: Codable, Sendable {
    let schemaVersion: Int
    let chunkingVersion: Int
    let embeddingModelID: String
    let embeddingRevision: Int
    let embeddingDimension: Int
    let updatedAt: Date
    let chunks: [MemoryChunk]

    static let currentSchemaVersion = 3
    static let currentChunkingVersion = 2
}

// MARK: - Entry Snapshot

struct IndexableEntry: Equatable, Sendable {
    let id: UUID
    let date: Date
    let mood: String?
    let text: String
    let isStarred: Bool
    let updatedAt: Date?

    init(id: UUID, date: Date, mood: String?, text: String, isStarred: Bool, updatedAt: Date? = nil) {
        self.id = id
        self.date = date
        self.mood = mood
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.isStarred = isStarred
        self.updatedAt = updatedAt
    }

    init?(entry: DiaryEntry) {
        guard let id = entry.id else { return nil }
        let text = (entry.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        self.id = id
        self.date = entry.date ?? entry.createdAt ?? Date()
        self.mood = entry.value(forKey: "mood") as? String
        self.text = text
        self.isStarred = entry.isStarred
        self.updatedAt = entry.updatedAt
    }
}

// MARK: - Embeddings

struct EmbeddingMetadata: Equatable, Codable, Sendable {
    let modelID: String
    let revision: Int
    let dimension: Int
    let language: String
}

struct EmbeddedText: Sendable {
    let vector: [Float]
    let metadata: EmbeddingMetadata
}

protocol EmbeddingProvider: Sendable {
    func embedding(for text: String, language: NLLanguage?) async throws -> EmbeddedText
}

enum EmbeddingProviderError: LocalizedError {
    case unavailable
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Semantic embedding assets are unavailable on this device."
        case .emptyResult:
            return "The semantic embedding model returned no vectors."
        }
    }
}

actor NLContextualEmbeddingProvider: EmbeddingProvider {
    private var loadedModels: [String: NLContextualEmbedding] = [:]

    func embedding(for text: String, language: NLLanguage?) async throws -> EmbeddedText {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw EmbeddingProviderError.emptyResult }

        let resolvedLanguage = language ?? NLLanguageRecognizer.dominantLanguage(for: trimmed) ?? .english
        let model = try await model(for: resolvedLanguage)
        let result = try model.embeddingResult(for: trimmed, language: resolvedLanguage)

        var sum = Array(repeating: 0.0, count: model.dimension)
        var count = 0.0
        result.enumerateTokenVectors(in: trimmed.startIndex..<trimmed.endIndex) { vector, _ in
            guard vector.count == sum.count else { return true }
            for index in vector.indices {
                sum[index] += vector[index]
            }
            count += 1
            return true
        }

        guard count > 0 else { throw EmbeddingProviderError.emptyResult }
        let pooled = sum.map { Float($0 / count) }
        let metadata = EmbeddingMetadata(
            modelID: model.modelIdentifier,
            revision: model.revision,
            dimension: model.dimension,
            language: resolvedLanguage.rawValue
        )
        return EmbeddedText(vector: VectorMath.normalized(pooled), metadata: metadata)
    }

    private func model(for language: NLLanguage) async throws -> NLContextualEmbedding {
        let key = language.rawValue
        if let model = loadedModels[key] {
            return model
        }

        guard let model = NLContextualEmbedding(language: language) ?? NLContextualEmbedding(language: .english) else {
            throw EmbeddingProviderError.unavailable
        }

        if !model.hasAvailableAssets {
            let result = await requestAssets(for: model)
            guard result == .available else { throw EmbeddingProviderError.unavailable }
        }

        try model.load()
        loadedModels[key] = model
        return model
    }

    private func requestAssets(for model: NLContextualEmbedding) async -> NLContextualEmbedding.AssetsResult {
        await withCheckedContinuation { continuation in
            model.requestAssets { result, _ in
                continuation.resume(returning: result)
            }
        }
    }
}

struct UnavailableEmbeddingProvider: EmbeddingProvider {
    let metadata = EmbeddingMetadata(modelID: "offrecord.lexical-fallback", revision: 1, dimension: 128, language: "und")

    func embedding(for text: String, language: NLLanguage?) async throws -> EmbeddedText {
        let tokens = TextSignals.tokens(in: text)
        var vector = Array(repeating: Float(0), count: metadata.dimension)
        for token in tokens {
            let digest = SHA256.hash(data: Data(token.utf8))
            let bucket = digest.withUnsafeBytes { bytes in
                let first = Int(bytes[0])
                let second = Int(bytes[1]) << 8
                return (first | second) % metadata.dimension
            }
            vector[bucket] += 1
        }
        return EmbeddedText(vector: VectorMath.normalized(vector), metadata: metadata)
    }
}

enum VectorMath {
    static func normalized(_ vector: [Float]) -> [Float] {
        guard !vector.isEmpty else { return vector }
        #if canImport(Accelerate)
        let magnitude = sqrt(vDSP.sumOfSquares(vector))
        guard magnitude > 0 else { return vector }
        return vDSP.divide(vector, magnitude)
        #else
        let magnitude = sqrt(vector.reduce(Float(0)) { $0 + $1 * $1 })
        guard magnitude > 0 else { return vector }
        return vector.map { $0 / magnitude }
        #endif
    }

    static func cosine(_ lhs: [Float], _ rhs: [Float]) -> Double {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return 0 }
        #if canImport(Accelerate)
        return Double(vDSP.dot(lhs, rhs))
        #else
        var sum = Float(0)
        for index in lhs.indices {
            sum += lhs[index] * rhs[index]
        }
        return Double(sum)
        #endif
    }
}

// MARK: - Chunking

struct MemoryChunkDraft: Equatable, Sendable {
    let text: String
    let characterStart: Int
    let characterEnd: Int
}

enum MemoryChunker {
    static func chunks(for text: String, targetWords: Int = 150, overlapWords: Int = 30) -> [MemoryChunkDraft] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let words = trimmed.split { $0.isWhitespace || $0.isNewline }
        if words.count <= targetWords {
            return [MemoryChunkDraft(text: trimmed, characterStart: 0, characterEnd: trimmed.count)]
        }

        let sentences = sentenceSlices(in: trimmed)
        var drafts: [MemoryChunkDraft] = []
        var current: [SentenceSlice] = []
        var currentWords = 0

        for sentence in sentences {
            if !current.isEmpty, currentWords + sentence.wordCount > targetWords {
                drafts.append(draft(from: current, in: trimmed))
                current = overlapSuffix(from: current, targetWords: overlapWords)
                currentWords = current.reduce(0) { $0 + $1.wordCount }
            }
            current.append(sentence)
            currentWords += sentence.wordCount
        }

        if !current.isEmpty {
            drafts.append(draft(from: current, in: trimmed))
        }

        return drafts
    }

    private struct SentenceSlice {
        let range: Range<String.Index>
        let start: Int
        let end: Int
        let wordCount: Int
    }

    private static func sentenceSlices(in text: String) -> [SentenceSlice] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var slices: [SentenceSlice] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sentence.isEmpty else { return true }
            slices.append(
                SentenceSlice(
                    range: range,
                    start: text.distance(from: text.startIndex, to: range.lowerBound),
                    end: text.distance(from: text.startIndex, to: range.upperBound),
                    wordCount: wordCount(sentence)
                )
            )
            return true
        }
        if slices.isEmpty {
            return [
                SentenceSlice(
                    range: text.startIndex..<text.endIndex,
                    start: 0,
                    end: text.count,
                    wordCount: wordCount(text)
                )
            ]
        }
        return slices
    }

    private static func draft(from slices: [SentenceSlice], in text: String) -> MemoryChunkDraft {
        guard let first = slices.first, let last = slices.last else {
            return MemoryChunkDraft(text: "", characterStart: 0, characterEnd: 0)
        }
        let chunkText = String(text[first.range.lowerBound..<last.range.upperBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        return MemoryChunkDraft(text: chunkText, characterStart: first.start, characterEnd: last.end)
    }

    private static func overlapSuffix(from slices: [SentenceSlice], targetWords: Int) -> [SentenceSlice] {
        guard targetWords > 0 else { return [] }
        var result: [SentenceSlice] = []
        var count = 0
        for slice in slices.reversed() {
            result.insert(slice, at: 0)
            count += slice.wordCount
            if count >= targetWords { break }
        }
        return result
    }

    private static func wordCount(_ text: String) -> Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }
}

// MARK: - Text Signals

enum TextSignals {
    static let stopWords: Set<String> = [
        "the", "and", "for", "that", "with", "this", "from", "have", "was", "were", "are", "but", "not",
        "you", "your", "about", "into", "today", "really", "just", "they", "them", "then", "than", "when",
        "what", "where", "how", "why", "who", "had", "has", "been", "being", "will", "would", "could",
        "should", "there", "their", "because", "feel", "felt", "feeling"
    ]

    static let conceptSynonyms: [String: Set<String>] = [
        "stress": ["stress", "stressed", "anxiety", "anxious", "pressure", "overwhelmed", "burnout", "tense", "worry", "worried"],
        "work": ["work", "office", "meeting", "deadline", "manager", "boss", "project", "job", "client", "shift"],
        "people": ["friend", "friends", "family", "mother", "father", "partner", "colleague", "coworker", "relationship", "people"],
        "missing": ["miss", "missing", "distant", "absence", "lonely", "alone", "nostalgic"],
        "decision": ["decide", "decided", "decision", "choice", "choose", "chose", "regret", "regretted", "should", "option"],
        "joy": ["happy", "happier", "joy", "grateful", "calm", "excited", "peaceful", "proud", "win"],
        "health": ["sleep", "tired", "energy", "health", "exercise", "walk", "run", "body", "sick", "therapy"],
        "growth": ["learn", "growth", "change", "better", "progress", "aware", "realized", "understand", "practice"]
    ]

    static func tokens(in text: String) -> [String] {
        text.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count > 2 && !stopWords.contains($0) }
    }

    static func expandedTokens(in text: String) -> Set<String> {
        var result = Set(tokens(in: text))
        for token in Array(result) {
            for (_, synonyms) in conceptSynonyms where synonyms.contains(token) {
                result.formUnion(synonyms)
            }
        }
        return result
    }

    static func extractEntities(from text: String) -> [String] {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        var values: [String] = []
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType, options: [.omitWhitespace, .joinNames]) { tag, range in
            guard tag == .personalName || tag == .placeName || tag == .organizationName else { return true }
            let value = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if value.count > 1 { values.append(value) }
            return true
        }
        return Array(Set(values)).sorted()
    }

    static func extractTopics(from text: String, limit: Int = 10) -> [String] {
        let counts = Dictionary(grouping: tokens(in: text), by: { $0 }).mapValues(\.count)
        return counts.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            return lhs.key < rhs.key
        }
        .prefix(limit)
        .map(\.key)
    }

    static func hash(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func slice(_ text: String, start: Int, end: Int) -> String {
        let safeStart = max(0, min(start, text.count))
        let safeEnd = max(safeStart, min(end, text.count))
        let lower = text.index(text.startIndex, offsetBy: safeStart)
        let upper = text.index(text.startIndex, offsetBy: safeEnd)
        return String(text[lower..<upper]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func snippet(from text: String, query: String, maxLength: Int = 170) -> String {
        let queryTokens = tokens(in: query)
        let lower = text.lowercased()
        let firstMatch = queryTokens.compactMap { lower.range(of: $0)?.lowerBound }.min()
        let startIndex: String.Index
        if let firstMatch {
            let offset = max(0, lower.distance(from: lower.startIndex, to: firstMatch) - 50)
            startIndex = text.index(text.startIndex, offsetBy: offset)
        } else {
            startIndex = text.startIndex
        }
        let endIndex = text.index(startIndex, offsetBy: min(maxLength, text.distance(from: startIndex, to: text.endIndex)), limitedBy: text.endIndex) ?? text.endIndex
        var snippet = String(text[startIndex..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        if startIndex > text.startIndex { snippet = "..." + snippet }
        if endIndex < text.endIndex { snippet += "..." }
        return snippet
    }
}

// MARK: - Hybrid Search

struct LexicalHit: Sendable {
    let chunkID: String
    let reason: EvidenceReference.MatchReason
}

struct HybridSearchResult: Sendable {
    let chunk: MemoryChunk
    let score: Double
    let reason: EvidenceReference.MatchReason
    let semanticScore: Double
    let lexicalRank: Int?
}

enum HybridMemorySearchService {
    static func search(query: String, chunks: [MemoryChunk], queryVector: [Float], lexicalHits: [LexicalHit], limit: Int = 18) -> [HybridSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let semantic = semanticRanking(chunks: chunks, queryVector: queryVector)
        let fused = fuse(semantic: semantic, lexicalHits: lexicalHits, chunks: chunks)

        return Array(fused.prefix(limit))
    }

    static func lexicalHits(query: String, chunks: [MemoryChunk], textByChunkID: [String: String], rankedChunkIDs: [String]) -> [LexicalHit] {
        let queryTokens = TextSignals.expandedTokens(in: query)
        let rankedSet = Set(rankedChunkIDs)
        guard !queryTokens.isEmpty else { return [] }

        let hits = chunks.compactMap { chunk -> LexicalHit? in
            guard rankedSet.contains(chunk.id), let text = textByChunkID[chunk.id] else { return nil }
            let entityMatch = chunk.entities.map { $0.lowercased() }.contains { query.lowercased().contains($0) }
            let exactPhrase = text.localizedCaseInsensitiveContains(query)
            let topicMatch = chunk.topics.contains { queryTokens.contains($0) }
            let reason: EvidenceReference.MatchReason
            if exactPhrase {
                reason = .exact
            } else if entityMatch || topicMatch {
                reason = .entity
            } else {
                reason = .meaning
            }
            return LexicalHit(chunkID: chunk.id, reason: reason)
        }
        let order = Dictionary(uniqueKeysWithValues: rankedChunkIDs.enumerated().map { ($0.element, $0.offset) })
        return hits.sorted { (order[$0.chunkID] ?? Int.max) < (order[$1.chunkID] ?? Int.max) }
    }

    private static func semanticRanking(chunks: [MemoryChunk], queryVector: [Float]) -> [(String, Double)] {
        chunks.map { chunk in
            (chunk.id, VectorMath.cosine(queryVector, chunk.vector))
        }
        .filter { $0.1 > 0 }
        .sorted { $0.1 > $1.1 }
    }

    private static func fuse(semantic: [(String, Double)], lexicalHits: [LexicalHit], chunks: [MemoryChunk]) -> [HybridSearchResult] {
        let chunkMap = Dictionary(uniqueKeysWithValues: chunks.map { ($0.id, $0) })
        let semanticScores = Dictionary(uniqueKeysWithValues: semantic)
        var scores: [String: Double] = [:]
        var reasons: [String: EvidenceReference.MatchReason] = [:]
        var lexicalRankByID: [String: Int] = [:]
        let k = 60.0

        for (rank, item) in semantic.enumerated() {
            scores[item.0, default: 0] += 1.0 / (k + Double(rank + 1))
            if reasons[item.0] == nil { reasons[item.0] = .meaning }
        }
        for (rank, hit) in lexicalHits.enumerated() {
            scores[hit.chunkID, default: 0] += 1.25 / (k + Double(rank + 1))
            lexicalRankByID[hit.chunkID] = rank
            if hit.reason == .exact || hit.reason == .entity || reasons[hit.chunkID] == nil {
                reasons[hit.chunkID] = hit.reason
            }
        }

        let now = Date()
        return scores.compactMap { id, score -> HybridSearchResult? in
            guard let chunk = chunkMap[id] else { return nil }
            let ageDays = Calendar.current.dateComponents([.day], from: chunk.date, to: now).day ?? 0
            let recencyBoost = max(0, 0.008 - Double(ageDays) * 0.00025)
            let starredBoost = chunk.isStarred ? 0.004 : 0
            let finalScore = score + recencyBoost + starredBoost
            let reason = reasons[id] ?? (recencyBoost > 0.004 ? .recent : .meaning)
            return HybridSearchResult(
                chunk: chunk,
                score: finalScore,
                reason: reason,
                semanticScore: semanticScores[id] ?? 0,
                lexicalRank: lexicalRankByID[id]
            )
        }
        .sorted { $0.score > $1.score }
    }
}

// MARK: - SQLite Sidecar

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private final class LocalSemanticIndexStore {
    private let url: URL
    private var db: OpaquePointer?

    init(url: URL) throws {
        self.url = url
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if os(iOS)
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.deletingLastPathComponent().path)
        #endif
        guard sqlite3_open(url.path, &db) == SQLITE_OK else {
            throw StoreError.open(message: lastError)
        }
        try execute("PRAGMA journal_mode=WAL;")
        try execute("PRAGMA foreign_keys=ON;")
        try migrate()
        #if os(iOS)
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
        #endif
    }

    deinit {
        sqlite3_close(db)
    }

    enum StoreError: LocalizedError {
        case open(message: String)
        case sql(message: String)

        var errorDescription: String? {
            switch self {
            case .open(let message), .sql(let message):
                return message
            }
        }
    }

    private var lastError: String {
        if let db {
            return String(cString: sqlite3_errmsg(db))
        }
        return "SQLite database is not open."
    }

    func loadChunks() throws -> MemoryIndexSnapshot? {
        guard let schema = try metadataValue("schemaVersion").flatMap(Int.init),
              let chunking = try metadataValue("chunkingVersion").flatMap(Int.init),
              schema == MemoryIndexSnapshot.currentSchemaVersion,
              chunking == MemoryIndexSnapshot.currentChunkingVersion else {
            return nil
        }

        var statement: OpaquePointer?
        let sql = """
        SELECT id, entryID, chunkIndex, date, mood, textHash, entryTextHash, characterStart, characterEnd,
               entities, topics, embeddingModelID, embeddingRevision, embeddingDimension, language, vector, isStarred
        FROM chunks ORDER BY date DESC, chunkIndex ASC;
        """
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.sql(message: lastError)
        }
        defer { sqlite3_finalize(statement) }

        var chunks: [MemoryChunk] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = string(statement, 0),
                  let entryIDString = string(statement, 1),
                  let entryID = UUID(uuidString: entryIDString),
                  let textHash = string(statement, 5),
                  let entryTextHash = string(statement, 6),
                  let entitiesJSON = string(statement, 9),
                  let topicsJSON = string(statement, 10),
                  let modelID = string(statement, 11),
                  let language = string(statement, 14) else { continue }

            let vector = data(statement, 15).map(Self.vector(from:)) ?? []
            chunks.append(
                MemoryChunk(
                    id: id,
                    entryID: entryID,
                    chunkIndex: Int(sqlite3_column_int(statement, 2)),
                    date: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3)),
                    mood: string(statement, 4),
                    textHash: textHash,
                    entryTextHash: entryTextHash,
                    characterStart: Int(sqlite3_column_int(statement, 7)),
                    characterEnd: Int(sqlite3_column_int(statement, 8)),
                    entities: Self.decodeStringArray(entitiesJSON),
                    topics: Self.decodeStringArray(topicsJSON),
                    embeddingModelID: modelID,
                    embeddingRevision: Int(sqlite3_column_int(statement, 12)),
                    embeddingDimension: Int(sqlite3_column_int(statement, 13)),
                    language: language,
                    vector: vector,
                    isStarred: sqlite3_column_int(statement, 16) == 1
                )
            )
        }

        let snapshot = MemoryIndexSnapshot(
            schemaVersion: schema,
            chunkingVersion: chunking,
            embeddingModelID: try metadataValue("embeddingModelID") ?? "",
            embeddingRevision: Int(try metadataValue("embeddingRevision") ?? "0") ?? 0,
            embeddingDimension: Int(try metadataValue("embeddingDimension") ?? "0") ?? 0,
            updatedAt: Date(timeIntervalSince1970: Double(try metadataValue("updatedAt") ?? "0") ?? 0),
            chunks: chunks
        )
        return snapshot
    }

    func replaceAll(chunks: [MemoryChunk], textByChunkID: [String: String]) throws {
        try transaction {
            try deleteAllLocked()
            try insert(chunks: chunks, textByChunkID: textByChunkID)
            try writeMetadata(chunks: chunks)
        }
        protectSidecarFiles()
    }

    func upsert(entryID: UUID, chunks: [MemoryChunk], textByChunkID: [String: String]) throws {
        try transaction {
            try deleteEntryLocked(entryID)
            try insert(chunks: chunks, textByChunkID: textByChunkID)
            try writeMetadata(chunks: chunks.isEmpty ? try loadChunks()?.chunks ?? [] : allChunksMerged(with: chunks, replacing: entryID))
        }
        protectSidecarFiles()
    }

    func deleteEntry(_ entryID: UUID) throws {
        try transaction {
            try deleteEntryLocked(entryID)
            try writeMetadata(chunks: try loadChunks()?.chunks ?? [])
        }
        protectSidecarFiles()
    }

    func deleteAll() throws {
        try transaction {
            try deleteAllLocked()
            try setMetadata("schemaVersion", "\(MemoryIndexSnapshot.currentSchemaVersion)")
            try setMetadata("chunkingVersion", "\(MemoryIndexSnapshot.currentChunkingVersion)")
            try setMetadata("updatedAt", "\(Date().timeIntervalSince1970)")
        }
        protectSidecarFiles()
    }

    func lexicalSearch(query: String, limit: Int) throws -> [String] {
        guard let matchQuery = Self.ftsQuery(for: query) else { return [] }
        var statement: OpaquePointer?
        let sql = """
        SELECT id FROM chunk_fts
        WHERE chunk_fts MATCH ?
        ORDER BY bm25(chunk_fts)
        LIMIT ?;
        """
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.sql(message: lastError)
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, matchQuery, -1, sqliteTransient)
        sqlite3_bind_int(statement, 2, Int32(limit))

        var ids: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let id = string(statement, 0) {
                ids.append(id)
            }
        }
        return ids
    }

    private func migrate() throws {
        try execute("""
        CREATE TABLE IF NOT EXISTS chunks (
            id TEXT PRIMARY KEY NOT NULL,
            entryID TEXT NOT NULL,
            chunkIndex INTEGER NOT NULL,
            date REAL NOT NULL,
            mood TEXT,
            textHash TEXT NOT NULL,
            entryTextHash TEXT NOT NULL,
            characterStart INTEGER NOT NULL,
            characterEnd INTEGER NOT NULL,
            entities TEXT NOT NULL,
            topics TEXT NOT NULL,
            embeddingModelID TEXT NOT NULL,
            embeddingRevision INTEGER NOT NULL,
            embeddingDimension INTEGER NOT NULL,
            language TEXT NOT NULL,
            vector BLOB NOT NULL,
            isStarred INTEGER NOT NULL
        );
        """)
        try execute("CREATE INDEX IF NOT EXISTS idx_chunks_entry ON chunks(entryID);")
        try execute("CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL);")
        try execute("CREATE VIRTUAL TABLE IF NOT EXISTS chunk_fts USING fts5(id UNINDEXED, entryID UNINDEXED, text, tokenize='unicode61');")
    }

    private func allChunksMerged(with newChunks: [MemoryChunk], replacing entryID: UUID) -> [MemoryChunk] {
        let current = (try? loadChunks()?.chunks) ?? []
        return current.filter { $0.entryID != entryID } + newChunks
    }

    private func insert(chunks: [MemoryChunk], textByChunkID: [String: String]) throws {
        let sql = """
        INSERT OR REPLACE INTO chunks
        (id, entryID, chunkIndex, date, mood, textHash, entryTextHash, characterStart, characterEnd, entities, topics,
         embeddingModelID, embeddingRevision, embeddingDimension, language, vector, isStarred)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        for chunk in chunks {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw StoreError.sql(message: lastError)
            }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_text(statement, 1, chunk.id, -1, sqliteTransient)
            sqlite3_bind_text(statement, 2, chunk.entryID.uuidString, -1, sqliteTransient)
            sqlite3_bind_int(statement, 3, Int32(chunk.chunkIndex))
            sqlite3_bind_double(statement, 4, chunk.date.timeIntervalSince1970)
            bindOptionalText(statement, 5, chunk.mood)
            sqlite3_bind_text(statement, 6, chunk.textHash, -1, sqliteTransient)
            sqlite3_bind_text(statement, 7, chunk.entryTextHash, -1, sqliteTransient)
            sqlite3_bind_int(statement, 8, Int32(chunk.characterStart))
            sqlite3_bind_int(statement, 9, Int32(chunk.characterEnd))
            sqlite3_bind_text(statement, 10, Self.encodeStringArray(chunk.entities), -1, sqliteTransient)
            sqlite3_bind_text(statement, 11, Self.encodeStringArray(chunk.topics), -1, sqliteTransient)
            sqlite3_bind_text(statement, 12, chunk.embeddingModelID, -1, sqliteTransient)
            sqlite3_bind_int(statement, 13, Int32(chunk.embeddingRevision))
            sqlite3_bind_int(statement, 14, Int32(chunk.embeddingDimension))
            sqlite3_bind_text(statement, 15, chunk.language, -1, sqliteTransient)
            let vectorData = Self.data(from: chunk.vector)
            _ = vectorData.withUnsafeBytes { buffer in
                sqlite3_bind_blob(statement, 16, buffer.baseAddress, Int32(vectorData.count), sqliteTransient)
            }
            sqlite3_bind_int(statement, 17, chunk.isStarred ? 1 : 0)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw StoreError.sql(message: lastError)
            }

            try insertFTS(chunk: chunk, text: textByChunkID[chunk.id] ?? "")
        }
    }

    private func insertFTS(chunk: MemoryChunk, text: String) throws {
        var statement: OpaquePointer?
        let sql = "INSERT INTO chunk_fts(id, entryID, text) VALUES (?, ?, ?);"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.sql(message: lastError)
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, chunk.id, -1, sqliteTransient)
        sqlite3_bind_text(statement, 2, chunk.entryID.uuidString, -1, sqliteTransient)
        let tokenText = TextSignals.tokens(in: text).joined(separator: " ")
        sqlite3_bind_text(statement, 3, tokenText, -1, sqliteTransient)
        while true {
            let result = sqlite3_step(statement)
            switch result {
            case SQLITE_DONE:
                return
            case SQLITE_ROW:
                continue
            default:
                throw StoreError.sql(message: lastError)
            }
        }
    }

    private func deleteEntryLocked(_ entryID: UUID) throws {
        try execute("DELETE FROM chunks WHERE entryID = ?;", bindings: [entryID.uuidString])
        try execute("DELETE FROM chunk_fts WHERE entryID = ?;", bindings: [entryID.uuidString])
    }

    private func deleteAllLocked() throws {
        try execute("DELETE FROM chunks;")
        try execute("DELETE FROM chunk_fts;")
    }

    private func writeMetadata(chunks: [MemoryChunk]) throws {
        let first = chunks.first
        try setMetadata("schemaVersion", "\(MemoryIndexSnapshot.currentSchemaVersion)")
        try setMetadata("chunkingVersion", "\(MemoryIndexSnapshot.currentChunkingVersion)")
        try setMetadata("embeddingModelID", first?.embeddingModelID ?? "")
        try setMetadata("embeddingRevision", "\(first?.embeddingRevision ?? 0)")
        try setMetadata("embeddingDimension", "\(first?.embeddingDimension ?? 0)")
        try setMetadata("updatedAt", "\(Date().timeIntervalSince1970)")
    }

    private func setMetadata(_ key: String, _ value: String) throws {
        try execute(
            "INSERT OR REPLACE INTO metadata(key, value) VALUES (?, ?);",
            bindings: [key, value]
        )
    }

    private func metadataValue(_ key: String) throws -> String? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT value FROM metadata WHERE key = ?;", -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.sql(message: lastError)
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, key, -1, sqliteTransient)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return string(statement, 0)
    }

    private func transaction(_ work: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE;")
        do {
            try work()
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    private func execute(_ sql: String, bindings: [String] = []) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.sql(message: lastError)
        }
        defer { sqlite3_finalize(statement) }
        for (index, value) in bindings.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), value, -1, sqliteTransient)
        }
        while true {
            let result = sqlite3_step(statement)
            switch result {
            case SQLITE_DONE:
                return
            case SQLITE_ROW:
                continue
            default:
                throw StoreError.sql(message: lastError)
            }
        }
    }

    private func string(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let pointer = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: pointer)
    }

    private func data(_ statement: OpaquePointer?, _ index: Int32) -> Data? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let bytes = sqlite3_column_blob(statement, index) else { return nil }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, index)))
    }

    private func bindOptionalText(_ statement: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value {
            sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func protectSidecarFiles() {
        #if os(iOS)
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path + suffix)
        }
        #endif
    }

    private static func encodeStringArray(_ values: [String]) -> String {
        guard let data = try? JSONEncoder().encode(values),
              let string = String(data: data, encoding: .utf8) else { return "[]" }
        return string
    }

    private static func decodeStringArray(_ string: String) -> [String] {
        guard let data = string.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return values
    }

    private static func data(from vector: [Float]) -> Data {
        vector.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
    }

    private static func vector(from data: Data) -> [Float] {
        data.withUnsafeBytes { rawBuffer in
            let buffer = rawBuffer.bindMemory(to: Float.self)
            return Array(buffer)
        }
    }

    private static func ftsQuery(for query: String) -> String? {
        let tokens = TextSignals.tokens(in: query)
        guard !tokens.isEmpty else { return nil }
        return tokens
            .prefix(8)
            .map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }
            .joined(separator: " OR ")
    }
}

// MARK: - Index Actor

private actor SemanticMemoryIndexActor {
    private var chunks: [MemoryChunk] = []
    private let preferredProvider: any EmbeddingProvider = NLContextualEmbeddingProvider()
    private let fallbackProvider = UnavailableEmbeddingProvider()
    private let store: LocalSemanticIndexStore

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let url = base.appendingPathComponent("OffRecordIndex", isDirectory: true).appendingPathComponent("semantic-memory.sqlite")
        self.store = try! LocalSemanticIndexStore(url: url)
    }

    func load() throws -> MemoryIndexSnapshot? {
        let snapshot = try store.loadChunks()
        chunks = snapshot?.chunks ?? []
        return snapshot
    }

    func needsRebuild(records: [IndexableEntry], forceRemoteReconcile: Bool) -> Bool {
        if forceRemoteReconcile { return true }
        let expectedHashes = Dictionary(uniqueKeysWithValues: records.map { ($0.id, TextSignals.hash($0.text)) })
        let expectedIDs = Set(expectedHashes.keys)
        let indexedIDs = Set(chunks.map(\.entryID))
        guard indexedIDs == expectedIDs else { return true }
        let indexedHashes = Dictionary(grouping: chunks, by: \.entryID).mapValues { Set($0.map(\.entryTextHash)) }
        return !expectedHashes.allSatisfy { entryID, hash in
            indexedHashes[entryID]?.contains(hash) == true
        }
    }

    func rebuildAll(records: [IndexableEntry], progress: @Sendable @escaping (IndexProgress) async -> Void) async throws -> MemoryIndexSnapshot {
        try Task.checkCancellation()
        await progress(IndexProgress(progress: 0, message: "Building semantic memory..."))
        guard !records.isEmpty else {
            try store.deleteAll()
            chunks = []
            return MemoryIndexSnapshot(
                schemaVersion: MemoryIndexSnapshot.currentSchemaVersion,
                chunkingVersion: MemoryIndexSnapshot.currentChunkingVersion,
                embeddingModelID: "",
                embeddingRevision: 0,
                embeddingDimension: 0,
                updatedAt: Date(),
                chunks: []
            )
        }

        let provider = await selectedProvider(sampleText: records.first?.text ?? "")
        var builtChunks: [MemoryChunk] = []
        var textByChunkID: [String: String] = [:]
        let total = max(records.count, 1)

        for (entryIndex, record) in records.enumerated() {
            try Task.checkCancellation()
            if ProcessInfo.processInfo.arguments.contains("-SemanticMemorySlowIndexingUITest") {
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }
            if shouldPauseForSystemConditions {
                await progress(IndexProgress(progress: Double(entryIndex) / Double(total), message: "Semantic memory paused to save power."))
                try await Task.sleep(nanoseconds: 800_000_000)
            }

            let (entryChunks, entryTexts) = try await chunksForEntry(record, provider: provider)
            builtChunks.append(contentsOf: entryChunks)
            textByChunkID.merge(entryTexts) { _, new in new }

            await progress(IndexProgress(progress: Double(entryIndex + 1) / Double(total), message: "Indexed \(entryIndex + 1) of \(records.count) entries..."))
        }

        try store.replaceAll(chunks: builtChunks, textByChunkID: textByChunkID)
        chunks = builtChunks
        return try store.loadChunks() ?? MemoryIndexSnapshot(
            schemaVersion: MemoryIndexSnapshot.currentSchemaVersion,
            chunkingVersion: MemoryIndexSnapshot.currentChunkingVersion,
            embeddingModelID: builtChunks.first?.embeddingModelID ?? "",
            embeddingRevision: builtChunks.first?.embeddingRevision ?? 0,
            embeddingDimension: builtChunks.first?.embeddingDimension ?? 0,
            updatedAt: Date(),
            chunks: builtChunks
        )
    }

    func upsertEntry(_ record: IndexableEntry) async throws -> MemoryIndexSnapshot {
        let provider = await selectedProvider(sampleText: record.text)
        let (entryChunks, textByChunkID) = try await chunksForEntry(record, provider: provider)
        try store.upsert(entryID: record.id, chunks: entryChunks, textByChunkID: textByChunkID)
        chunks.removeAll { $0.entryID == record.id }
        chunks.append(contentsOf: entryChunks)
        return try store.loadChunks() ?? snapshotFallback()
    }

    func deleteEntry(id: UUID) throws -> MemoryIndexSnapshot {
        try store.deleteEntry(id)
        chunks.removeAll { $0.entryID == id }
        return try store.loadChunks() ?? snapshotFallback()
    }

    func deleteAll() throws {
        try store.deleteAll()
        chunks = []
    }

    func search(query: String, records: [IndexableEntry], limit: Int) async -> SemanticMemorySearchResult {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .ready([]) }
        guard !chunks.isEmpty else { return .unavailable("Semantic memory is not indexed yet.") }

        let provider = providerForCurrentIndex()
        let language = NLLanguageRecognizer.dominantLanguage(for: trimmed)
        let embedded: EmbeddedText
        do {
            embedded = try await provider.embedding(for: trimmed, language: language)
        } catch {
            return .failed(error.localizedDescription)
        }

        let recordByID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        let lexicalIDs: [String]
        do {
            lexicalIDs = try store.lexicalSearch(query: trimmed, limit: max(limit * 3, 24))
        } catch {
            return .failed(error.localizedDescription)
        }

        let lexicalCandidateIDs = Set(lexicalIDs)
        let textByChunkID = Dictionary(uniqueKeysWithValues: chunks.compactMap { chunk -> (String, String)? in
            guard lexicalCandidateIDs.contains(chunk.id), let record = recordByID[chunk.entryID] else { return nil }
            return (chunk.id, TextSignals.slice(record.text, start: chunk.characterStart, end: chunk.characterEnd))
        })
        let lexicalHits = HybridMemorySearchService.lexicalHits(query: trimmed, chunks: chunks, textByChunkID: textByChunkID, rankedChunkIDs: lexicalIDs)
        let results = HybridMemorySearchService.search(query: trimmed, chunks: chunks, queryVector: embedded.vector, lexicalHits: lexicalHits, limit: limit)

        let evidence = results.compactMap { result -> EvidenceReference? in
            guard let record = recordByID[result.chunk.entryID] else { return nil }
            let chunkText = TextSignals.slice(record.text, start: result.chunk.characterStart, end: result.chunk.characterEnd)
            guard !chunkText.isEmpty else { return nil }
            return EvidenceReference(
                id: result.chunk.id,
                entryID: result.chunk.entryID,
                date: result.chunk.date,
                mood: result.chunk.mood,
                snippet: TextSignals.snippet(from: chunkText, query: trimmed),
                chunkText: chunkText,
                score: result.score,
                matchReason: result.reason
            )
        }
        return .ready(evidence)
    }

    private func selectedProvider(sampleText: String) async -> any EmbeddingProvider {
        if ProcessInfo.processInfo.arguments.contains("-SemanticMemoryUseFallbackEmbeddings") {
            return fallbackProvider
        }
        guard !sampleText.isEmpty else { return fallbackProvider }
        do {
            _ = try await preferredProvider.embedding(for: sampleText, language: NLLanguageRecognizer.dominantLanguage(for: sampleText))
            return preferredProvider
        } catch {
            return fallbackProvider
        }
    }

    private func providerForCurrentIndex() -> any EmbeddingProvider {
        guard let first = chunks.first else { return fallbackProvider }
        return first.embeddingModelID == fallbackProvider.metadata.modelID ? fallbackProvider : preferredProvider
    }

    private func chunksForEntry(_ record: IndexableEntry, provider: any EmbeddingProvider) async throws -> ([MemoryChunk], [String: String]) {
        let drafts = MemoryChunker.chunks(for: record.text)
        var result: [MemoryChunk] = []
        var textByChunkID: [String: String] = [:]
        let entryTextHash = TextSignals.hash(record.text)

        for (chunkIndex, draft) in drafts.enumerated() {
            let language = NLLanguageRecognizer.dominantLanguage(for: draft.text)
            let embedded = try await provider.embedding(for: draft.text, language: language)
            let textHash = TextSignals.hash(draft.text)
            let chunkID = "\(record.id.uuidString)-\(chunkIndex)-\(textHash.prefix(12))"
            result.append(
                MemoryChunk(
                    id: chunkID,
                    entryID: record.id,
                    chunkIndex: chunkIndex,
                    date: record.date,
                    mood: record.mood,
                    textHash: textHash,
                    entryTextHash: entryTextHash,
                    characterStart: draft.characterStart,
                    characterEnd: draft.characterEnd,
                    entities: TextSignals.extractEntities(from: draft.text),
                    topics: TextSignals.extractTopics(from: draft.text),
                    embeddingModelID: embedded.metadata.modelID,
                    embeddingRevision: embedded.metadata.revision,
                    embeddingDimension: embedded.vector.count,
                    language: language?.rawValue ?? embedded.metadata.language,
                    vector: embedded.vector,
                    isStarred: record.isStarred
                )
            )
            textByChunkID[chunkID] = draft.text
        }
        return (result, textByChunkID)
    }

    private func snapshotFallback() -> MemoryIndexSnapshot {
        let first = chunks.first
        return MemoryIndexSnapshot(
            schemaVersion: MemoryIndexSnapshot.currentSchemaVersion,
            chunkingVersion: MemoryIndexSnapshot.currentChunkingVersion,
            embeddingModelID: first?.embeddingModelID ?? "",
            embeddingRevision: first?.embeddingRevision ?? 0,
            embeddingDimension: first?.embeddingDimension ?? 0,
            updatedAt: Date(),
            chunks: chunks
        )
    }

    private var shouldPauseForSystemConditions: Bool {
        ProcessInfo.processInfo.isLowPowerModeEnabled || ProcessInfo.processInfo.thermalState == .serious || ProcessInfo.processInfo.thermalState == .critical
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

    private let worker = SemanticMemoryIndexActor()
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
            ? "Semantic memory is ready with lexical fallback. Apple embedding assets were unavailable."
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
        let searchResult = await SemanticMemoryIndexController.shared.search(query: question, entries: entries, limit: 6)

        switch searchResult {
        case .building(let progress, let message):
            return EvidenceBackedFridayAnswer(
                summary: "Friday is still building semantic memory.",
                observations: [EvidenceObservation(text: "\(message) \(Int(progress * 100))% complete.", evidenceIDs: [])],
                evidence: [],
                confidence: 0,
                followUpPrompt: "Try again when indexing finishes.",
                limitations: "Friday will not answer from a partially built index."
            )
        case .unavailable(let reason):
            return EvidenceBackedFridayAnswer(
                summary: "I do not have enough journal evidence to answer that yet.",
                observations: [EvidenceObservation(text: reason, evidenceIDs: [])],
                evidence: [],
                confidence: 0,
                followUpPrompt: "What part of this do you want to start tracking?",
                limitations: "Friday only answers from entries stored on this device."
            )
        case .failed(let message):
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

        guard !strongEvidence.isEmpty else {
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
