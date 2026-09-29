import Foundation
import Testing
@testable import SemanticMemoryKit
import JournalFoundation

struct SemanticMemoryKitTests {

    private func tempStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("semantic-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("index.sqlite")
    }

    private func entry(_ text: String, id: UUID = UUID(), mood: String? = "calm", starred: Bool = false) -> IndexableEntry {
        IndexableEntry(
            id: id,
            date: Date(timeIntervalSince1970: 1_750_000_000),
            mood: mood,
            text: text,
            isStarred: starred
        )
    }

    // MARK: Chunking

    @Test func shortTextYieldsSingleChunk() {
        let drafts = MemoryChunker.chunks(for: "A short entry about a walk in the park.")
        #expect(drafts.count == 1)
        #expect(drafts[0].characterStart == 0)
    }

    @Test func longTextChunksWithOverlap() {
        let sentence = "Today I worked on the reliability review and felt focused. "
        let text = String(repeating: sentence, count: 40)
        let drafts = MemoryChunker.chunks(for: text, targetWords: 50, overlapWords: 10)
        #expect(drafts.count > 1)
        #expect(drafts.allSatisfy { !$0.text.isEmpty })
    }

    // MARK: Hybrid search lifecycle with the fallback provider

    @Test func lifecycleIndexSearchDeleteWorks() async throws {
        let bangaloreID = UUID()
        let records = [
            entry("I visited a cafe in Bangalore and wrote about the trip.", id: bangaloreID),
            entry("Work stress kept me up; the deadline pressure was intense."),
            entry("A calm morning walk with grateful thoughts about family."),
        ]
        let provider = UnavailableEmbeddingProvider()
        let worker = SemanticMemoryIndexActor(
            storeURL: tempStoreURL(),
            preferredProvider: provider,
            fallbackProvider: provider
        )

        let snapshot = try await worker.rebuildAll(records: records) { _ in }
        #expect(snapshot.chunks.count == records.count)

        let search = await worker.search(query: "Bangalore cafe", records: records, limit: 6)
        guard case .ready(let evidence) = search else {
            Issue.record("expected ready result, got \(search)")
            return
        }
        #expect(evidence.contains { $0.entryID == bangaloreID })

        _ = try await worker.deleteEntry(id: bangaloreID)
        let afterDelete = await worker.search(query: "Bangalore cafe", records: records.filter { $0.id != bangaloreID }, limit: 6)
        if case .ready(let remaining) = afterDelete {
            #expect(!remaining.contains { $0.entryID == bangaloreID })
        }
    }

    // MARK: Staleness

    private func fallbackWorker(storeURL: URL) -> SemanticMemoryIndexActor {
        let provider = UnavailableEmbeddingProvider()
        return SemanticMemoryIndexActor(storeURL: storeURL, preferredProvider: provider, fallbackProvider: provider)
    }

    /// Friday and Timeline check this before every search; a spurious `true`
    /// rebuilds the whole index and leaves Friday "still reading".
    @Test func unchangedJournalNeverNeedsRebuild() async throws {
        let storeURL = tempStoreURL()
        let long = String(repeating: "Work stress made the week heavy, so I walked after dinner to reset. ", count: 40)
        let records = [
            entry("A calm morning walk with grateful thoughts about family."),
            entry(long, mood: "anxious", starred: true),
            entry("No mood picked for this one.", mood: nil),
        ]
        #expect(MemoryChunker.chunks(for: long).count > 1)

        let worker = fallbackWorker(storeURL: storeURL)
        #expect(await worker.needsRebuild(records: records))
        _ = try await worker.rebuildAll(records: records) { _ in }
        #expect(await !worker.needsRebuild(records: records))
        #expect(await !worker.needsRebuild(records: records))

        // After a relaunch the index comes back from disk.
        let relaunched = fallbackWorker(storeURL: storeURL)
        _ = try await relaunched.load()
        #expect(await !relaunched.needsRebuild(records: records))
    }

    @Test func addedRemovedOrEditedEntriesNeedRebuild() async throws {
        let coffee = entry("Coffee with Maya after the review.")
        let run = entry("Evening run by the river.")
        let worker = fallbackWorker(storeURL: tempStoreURL())
        _ = try await worker.rebuildAll(records: [coffee, run]) { _ in }

        #expect(await worker.needsRebuild(records: [coffee]))
        #expect(await worker.needsRebuild(records: [coffee, run, entry("A new entry from another device.")]))
        #expect(await worker.needsRebuild(records: [entry("Coffee with Maya after the long review.", id: coffee.id), run]))
        #expect(await worker.needsRebuild(records: [entry(coffee.text, id: coffee.id, mood: "happy"), run]))
        #expect(await worker.needsRebuild(records: [entry(coffee.text, id: coffee.id, starred: true), run]))
    }

    @Test func upsertedEditLeavesIndexCurrent() async throws {
        let coffee = entry("Coffee with Maya after the review.")
        let run = entry("Evening run by the river.")
        let worker = fallbackWorker(storeURL: tempStoreURL())
        _ = try await worker.rebuildAll(records: [coffee, run]) { _ in }

        let edited = entry("Coffee with Maya after the long review.", id: coffee.id, mood: "happy", starred: true)
        _ = try await worker.upsertEntry(edited)
        #expect(await !worker.needsRebuild(records: [edited, run]))
    }

    // MARK: Exclusion contract

    @Test func exclusionPermissionsGateSemanticIndexing() {
        #expect(JournalAIExclusion.included.permitsSemanticIndexing)
        #expect(!JournalAIExclusion.excludedFromAI.permitsSemanticIndexing)
        #expect(!JournalAIExclusion.excludedFromAIAndReflection.permitsSemanticIndexing)
    }

    /// The host-app ingest gate pattern: excluded entries never become
    /// records, so they can never surface in results.
    @Test func excludedEntryNeverSurfacesInSearch() async throws {
        let secretID = UUID()
        let included = entry("Planning a surprise picnic near the lake with friends.")
        let excludedSnapshotText = "A private confession about the Bangalore cafe meeting."

        // Simulates the app-side gate: only included entries are ingested.
        func gate(_ text: String, id: UUID, exclusion: JournalAIExclusion) -> IndexableEntry? {
            guard exclusion.permitsSemanticIndexing else { return nil }
            return entry(text, id: id)
        }

        let records = [
            gate(included.text, id: included.id, exclusion: .included),
            gate(excludedSnapshotText, id: secretID, exclusion: .excludedFromAI),
        ].compactMap { $0 }

        #expect(records.count == 1)

        let provider = UnavailableEmbeddingProvider()
        let worker = SemanticMemoryIndexActor(
            storeURL: tempStoreURL(),
            preferredProvider: provider,
            fallbackProvider: provider
        )
        _ = try await worker.rebuildAll(records: records) { _ in }

        let search = await worker.search(query: "Bangalore cafe confession", records: records, limit: 10)
        if case .ready(let evidence) = search {
            #expect(!evidence.contains { $0.entryID == secretID })
        }
    }

    // MARK: Text signals

    @Test func expandedTokensIncludeConceptSynonyms() {
        let tokens = TextSignals.expandedTokens(in: "deadline pressure at the office")
        #expect(tokens.contains("stress"))
        #expect(tokens.contains("work"))
    }

    @Test func hashIsStable() {
        #expect(TextSignals.hash("abc") == TextSignals.hash("abc"))
        #expect(TextSignals.hash("abc") != TextSignals.hash("abd"))
    }
}
