//
//  SemanticMemoryTestSupport.swift
//  SemanticMemoryKit
//

import Foundation

#if DEBUG
public struct SemanticMemoryLifecycleTestResult: Sendable {
    public let initialChunkCount: Int
    public let updatedChunkCount: Int
    public let deletedChunkCount: Int
    public let updatedSearchMatchedNewText: Bool
    public let deletedSearchHasRemovedEntry: Bool
}

public enum SemanticMemoryTestSupport {
    public static func loadSnapshotAfterProviderMetadataMismatch(
        url: URL,
        chunk: MemoryChunk,
        text: String
    ) throws -> MemoryIndexSnapshot? {
        let store = try LocalSemanticIndexStore(url: url)
        try store.replaceAll(chunks: [chunk], textByChunkID: [chunk.id: text])
        try store.overwriteMetadataForTesting(key: "embeddingModelID", value: "offrecord.old-provider")
        return try store.loadChunks()
    }

    public static func loadSnapshotAfterSchemaMismatch(
        url: URL,
        chunk: MemoryChunk,
        text: String
    ) throws -> MemoryIndexSnapshot? {
        let store = try LocalSemanticIndexStore(url: url)
        try store.replaceAll(chunks: [chunk], textByChunkID: [chunk.id: text])
        try store.overwriteMetadataForTesting(key: "schemaVersion", value: "\(MemoryIndexSnapshot.currentSchemaVersion - 1)")
        return try store.loadChunks()
    }

    public static func exerciseLifecycle(
        url: URL,
        initialRecords: [IndexableEntry],
        updatedRecord: IndexableEntry,
        deletedEntryID: UUID
    ) async throws -> SemanticMemoryLifecycleTestResult {
        let provider = UnavailableEmbeddingProvider()
        let actor = SemanticMemoryIndexActor(
            storeURL: url,
            preferredProvider: provider,
            fallbackProvider: provider
        )

        let initial = try await actor.rebuildAll(records: initialRecords) { _ in }
        let updated = try await actor.upsertEntry(updatedRecord)
        let updatedRecords = initialRecords.map { $0.id == updatedRecord.id ? updatedRecord : $0 }
        let updatedSearch = await actor.search(query: updatedRecord.text, records: updatedRecords, limit: 6)

        let deleted = try await actor.deleteEntry(id: deletedEntryID)
        let remainingRecords = updatedRecords.filter { $0.id != deletedEntryID }
        let deletedSearch = await actor.search(query: "Bangalore cafe", records: remainingRecords, limit: 6)

        let updatedMatchedNewText: Bool
        if case .ready(let evidence) = updatedSearch {
            updatedMatchedNewText = evidence.contains {
                $0.entryID == updatedRecord.id && $0.chunkText.localizedCaseInsensitiveContains(updatedRecord.text)
            }
        } else {
            updatedMatchedNewText = false
        }

        let deletedHasRemovedEntry: Bool
        if case .ready(let evidence) = deletedSearch {
            deletedHasRemovedEntry = evidence.contains { $0.entryID == deletedEntryID }
        } else {
            deletedHasRemovedEntry = false
        }

        return SemanticMemoryLifecycleTestResult(
            initialChunkCount: initial.chunks.count,
            updatedChunkCount: updated.chunks.count,
            deletedChunkCount: deleted.chunks.count,
            updatedSearchMatchedNewText: updatedMatchedNewText,
            deletedSearchHasRemovedEntry: deletedHasRemovedEntry
        )
    }
}
#endif
