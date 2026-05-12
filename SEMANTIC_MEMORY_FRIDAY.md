# Semantic Memory Search + Evidence-Based Friday

## Summary

Semantic Memory is OffRecord's local memory layer for finding journal entries by meaning, not only by exact words. Evidence-Based Friday uses that same retrieval layer to answer questions only when the user's own entries provide enough support.

The product invariant is retrieval first, generation second. Friday must not invent evidence. If the index is unavailable, still building, contradictory, or too weak for the question, Friday should say the journal does not contain enough evidence yet.

## User-Facing Behavior

- Timeline search can return conceptually related entries even when the query words do not appear verbatim.
- Exact names, places, topics, starred entries, recency, mood filters, and date filters still influence ranking.
- Friday free-form questions retrieve journal evidence before answering.
- Suggested Friday chips keep the existing profile-summary behavior, but attach citations when retrieved evidence supports the response.
- Evidence chips show the source date, mood, snippet, match reason, and deep-link target for the matching entry.
- Settings includes Semantic Memory controls for status, rebuild, and local index deletion.

## Architecture

Semantic Memory is a local-only sidecar around the existing journal store. Journal entries remain in Core Data with optional CloudKit sync. Derived embeddings, chunk metadata, and lexical search rows are stored per device and can be rebuilt from synced entries.

Core components:

- `SemanticMemoryIndexController` is the UI-facing coordinator. It publishes status/progress, bridges app events into index work, and exposes typed search states.
- `SemanticMemoryIndexActor` owns background indexing and search work. It accepts immutable `IndexableEntry` values so embedding, chunking, and sidecar writes do not run on the main actor.
- `MemoryChunker` splits entries by sentence and paragraph boundaries, preserving offsets so snippets can be recovered from the source entry.
- `EmbeddingProvider` defines the embedding boundary.
- `NLContextualEmbeddingProvider` is the default first-party, on-device provider.
- `UnavailableEmbeddingProvider` gives deterministic unavailable/fallback behavior when embedding assets cannot be used.
- `LocalSemanticIndexStore` stores vector blobs, chunk metadata, search state, and the SQLite FTS sidecar.
- `HybridMemorySearchService` combines semantic and lexical retrieval with ranking boosts.
- `EvidenceFridayEngine` retrieves evidence first, builds evidence-backed answers, and refuses unsupported questions.
- `FoundationModelsFridayResponder` is optional and availability-gated. It can improve phrasing, but it is never the source of truth for evidence.

High-level data flow:

```text
DiaryEntry (Core Data / optional CloudKit)
    -> IndexableEntry snapshot
    -> SemanticMemoryIndexActor
    -> MemoryChunker
    -> EmbeddingProvider
    -> LocalSemanticIndexStore (vectors + FTS sidecar)
    -> HybridMemorySearchService
    -> Timeline results / EvidenceFridayEngine
    -> EvidenceReference chips and entry deep links
```

## Data And Privacy

- Journal entries remain in the existing Core Data store and optional CloudKit sync path.
- The semantic index is derived data stored locally in the app container.
- Embeddings and the SQLite FTS sidecar are not synced through CloudKit.
- The index is rebuildable per device from journal entries.
- Apple embedding asset downloads may fetch model files only. Journal text remains on device.
- The lexical sidecar should avoid storing full journal plaintext when offsets can recover snippets from Core Data.
- Deleting the semantic index must not delete entries, photos, audio, exports, widgets, or iCloud data.
- Rebuilding the semantic index must not mutate journal content.

Security-sensitive implementation constraints:

- Do not add developer-server or third-party transmission for journal text, embeddings, snippets, or Friday prompts.
- Do not make derived embeddings part of CloudKit journal sync.
- Keep file protection aligned with other local journal-derived data.
- Treat embeddings and tokenized lexical rows as sensitive derived data, not anonymous telemetry.
- Keep Settings controls for delete and rebuild operational after schema or provider changes.

## Index Lifecycle

- First feature use can trigger an index build when no usable local index exists.
- Create and edit flows enqueue `upsertEntry` work.
- Delete flows enqueue `deleteEntry` work and remove orphan chunks.
- Remote CloudKit changes mark the index for reconciliation, then updated entries are reindexed from local Core Data snapshots.
- Schema version, embedding model identifier, model revision, dimension, language, provider, and chunking version can invalidate the index.
- Low Power Mode and serious thermal pressure can pause or throttle non-urgent indexing.
- Build work must be cancellable and must not block recording, transcription, entry editing, or navigation.

Search returns typed states:

- `ready([EvidenceReference])` when retrieval has completed.
- `building(progress)` when the index is still being created or reconciled.
- `unavailable(reason)` when embedding assets or local index prerequisites are unavailable.
- `failed(error)` when the search/index path hit a recoverable failure that should be visible in UI copy.

## Search Behavior

Entries are split into chunks that target compact, meaningful passages. Short entries remain one chunk. Longer entries use sentence and paragraph boundaries where possible, with offsets retained for snippet recovery and highlighting.

Search combines:

- Semantic retrieval over normalized `Float32` vectors.
- Lexical retrieval from the SQLite FTS sidecar.
- Ranking boosts for exact people, places, topics, starred entries, recency, and active mood/date filters.

The expected product behavior is hybrid, not vector-only. Names like `Maya`, locations like `Bangalore`, and user-specific terms should remain highly ranked even when semantic matches are also available.

## Friday Behavior

Friday has two evidence modes:

- Suggested chips can use existing profile metrics and summaries, but should attach evidence chips when supporting entries are found.
- Free-form questions must retrieve evidence before answering.

Every substantive observation in a Friday answer must map to real `EvidenceReference` IDs. Unsupported generated observations should be dropped or downgraded to a limitation. If the available evidence is missing, weak, contradictory, unavailable, or still indexing, Friday should hedge or refuse instead of fabricating a claim.

Foundation Models integration is optional. On supported iOS 26 Apple Intelligence-capable devices, it may improve wording after evidence retrieval succeeds. The responder must still validate that generated observations cite retrieved evidence. iOS 17-25 users get deterministic evidence-backed fallback behavior.

## Testing And QA

Automated coverage should include:

- Chunk boundary behavior and offset preservation.
- Text hashing and schema/model invalidation.
- Vector normalization and cosine similarity.
- Hybrid semantic/lexical ranking and exact-name boosts.
- Typed search state transitions.
- Build cancellation, delete/rebuild races, and orphan chunk deletion.
- Mixed provider and unavailable-provider behavior.
- Friday no-evidence, weak-evidence, contradiction, and citation validation paths.

Manual QA should include:

- Simulator smoke with seeded journal data.
- Real-device testing for `NLContextualEmbedding` asset availability.
- iOS 17/18 deterministic fallback behavior.
- iOS 26 Apple Intelligence availability checks when a capable device is available.
- Low Power Mode and thermal-throttling behavior during rebuild.
- Offline rebuild/search behavior, especially asset-unavailable messaging.
- Evidence chip deep links from Friday into the correct entry.

Useful launch arguments for manual and UI testing:

```text
-UITesting -ScreenshotMode
-SemanticMemoryUITest
-SemanticMemoryUseFallbackEmbeddings
```

## Contributor Checklist

Before changing this feature:

- Keep the index local-only and rebuildable.
- Keep the main actor limited to status/progress and UI updates.
- Preserve typed search states instead of collapsing errors into empty results.
- Preserve entry offsets so evidence chips and highlighting point back to source text.
- Add or update tests when changing chunking, ranking, provider metadata, lifecycle operations, or Friday answer rules.
- Do not let Foundation Models or any future responder produce unsupported observations.

Related implementation files:

- `OffRecord/SemanticMemory.swift`
- `OffRecord/FoundationModelsFridayResponder.swift`
- `OffRecord/FridayAssistantEngine.swift`
- `OffRecord/FridayChatView.swift`
- `OffRecord/TimelineView.swift`
- `OffRecord/SettingsView.swift`
