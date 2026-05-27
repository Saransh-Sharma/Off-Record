# OffRecord AI Journal Architecture

This document describes the high-level architecture of OffRecord AI Journal to help contributors understand the codebase.

## Data Flow

```
Microphone → AudioRecorder (AAC 44.1kHz)
    ↓
SpeechTranscriber (SFSpeechRecognizer, on-device)
    ↓
LocalAIEngine + InsightsEngine (NLTagger analysis)
    ↓
FridayAssistantEngine (personality modeling)
    ↓
Persistence (Core Data + optional CloudKit)
    ↓
UI (SwiftUI, WidgetKit, AppIntents)
    ↓
System Discoverability (App Shortcuts + Spotlight metadata + deep links)
    ↓
Semantic Memory Index (local-only vectors + FTS)
    ↓
Timeline Search + Evidence-Based Friday
    ↓
UI evidence chips, search reasons, and entry deep links
```

## Weekly Reflection Flow

Weekly Reflection is a local, deterministic weekly report layer over started journal entries. It does not add a Core Data migration; reports and settings are encoded into existing AI state.

```
Started DiaryEntry values
    ↓
WeeklyReflectionEntrySnapshot (date, mood, words, source type, sentiment, text)
    ↓
WeeklyReflectionEligibilityService (Monday-Sunday period + thresholds)
    ↓
WeeklyReflectionSafetyFilter (high-risk entries excluded from generated insights)
    ↓
WeeklyReflectionGenerationService (themes, summary, wins, frictions, questions)
    ↓
WeeklyReflectionRepository (Codable payload in AIState)
    ↓
Home card / Report detail / Insights history / Settings / Local notification
```

Important behavior:

- Empty means zero entries or fewer than 150 words.
- Light means 1-2 entries and 150-599 words.
- Full means 3+ entries with at least 150 words, or 600+ words.
- High-risk entries count for eligibility and source management but are not used for generated themes, snippets, evidence quotes, wins, frictions, questions, or export quotes.
- Regeneration creates a new version, supersedes the previous version, and stores hidden source IDs only on that report version.

## Apple Watch Quick Capture Flow

The watchOS 26+ companion is a capture/outbox surface. The iPhone app remains the canonical journal.

```
Apple Watch Home
    ↓
Mood / Speak / Record
    ↓
WatchCaptureEnvelope + optional WatchAudioManifest
    ↓
Durable watch outbox
    ↓
WCSession.transferUserInfo(metadata) / WCSession.transferFile(audio)
    ↓
WatchCaptureImporter on iPhone
    ↓
Daily DiaryEntry mood/text update or AudioAttachment insert
    ↓
WatchImportReceipt sent back to watch
    ↓
Watch outbox marks capture synced and purges transferred audio
```

### Watch Queue Guarantees

- The watch persists the full outbox and exposes only a 20-item Recent projection.
- Each queued row stores sync state, transfer kind, attempt count, last attempt, next attempt, last error, and missing-file state.
- `.sending` rows become retryable after a stale interval; failed rows retry with bounded backoff when eligible.
- Audio captures never fall back to metadata-only import. If the file is missing on watch, the row is marked failed instead of pretending it synced.
- The watch applies storage caps for metadata and audio files, removes orphaned/synced audio files, and keeps complications/Smart Stack content privacy-safe.

### iPhone Import Guarantees

- `WatchCaptureImporter` is idempotent by `captureID` using local-only `WatchImportReceipt` rows.
- Mood captures update the daily entry mood for the capture date.
- Speak captures append dictated text to the daily entry.
- Record captures are two-phase: metadata may be observed, but the audio file must arrive before an `AudioAttachment` and receipt are created.
- Audio attachments dedupe by `sourceCaptureID`; duplicate transfers do not create duplicate journal audio.
- Staged temporary files are removed on duplicate, failure, or successful import.

## Module Overview

Core iPhone source files are in `OffRecord/`. Shared watch/iPhone capture models live in `OffRecordShared/`. The watch app and widget targets live in `OffRecordWatch/` and `OffRecordWatchWidget/`.

### Core Pipeline

| Module | File | Responsibility |
|---|---|---|
| **AudioRecorder** | `AudioRecorder.swift` | AVAudioRecorder wrapper. Records AAC at 44.1kHz, provides real-time audio levels. Stores recordings in the app sandbox. |
| **SpeechTranscriber** | `SpeechTranscriber.swift` | Speech-to-text via Apple Speech after explicit consent. Offline-capable paths require on-device recognition when available; online transcription may be processed by Apple Speech. |
| **LocalAIEngine** | `LocalAIEngine.swift` | NLP analysis using NaturalLanguage framework. Sentiment analysis, topic extraction, intent recognition. Maintains a UserProfile for learned patterns. |
| **InsightsEngine** | `InsightsEngine.swift` | Generates insight cards from journal data. Sentiment trends, topic frequency, journaling patterns. |
| **FridayAssistantEngine** | `FridayAssistantEngine.swift` | Core personality model with four sub-models (see below). Processes NLTagger output per entry. Serializes to JSON in Core Data (~12 KB). |
| **Semantic Memory** | `SemanticMemory.swift` | Local-only chunking, embeddings, hybrid search, index lifecycle, and evidence references. |
| **Weekly Reflection** | `WeeklyReflectionModels.swift`, `WeeklyReflectionServices.swift`, `WeeklyReflectionController.swift` | Local weekly eligibility, deterministic report generation, safety filtering, AIState persistence, report versioning, export, and local notification scheduling. |
| **Foundation Models Friday** | `FoundationModelsFridayResponder.swift` | Optional iOS 26 phrasing layer that validates observations against retrieved evidence. |
| **Persistence** | `Persistence.swift` | Core Data with NSPersistentCloudKitContainer. Stores entries, synced photo attachments, audio metadata, and AI state. App Group for WidgetKit data sharing. |
| **System Discoverability** | `AppIntents.swift`, `JournalSpotlightIndexer.swift`, `OffRecordNavigationRouter.swift` | App Shortcuts, privacy-safe `JournalEntryEntity`, Core Spotlight metadata indexing, NSUserActivity prediction/search donation, and `offrecord://` route handling. |
| **Watch Capture Import** | `WatchCaptureImporter.swift`, `AudioAttachmentStore.swift` | WatchConnectivity receiver, daily-entry import, local-only receipts, multi-audio attachment storage, and duplicate replay protection. |
| **Watch Shared Models** | `OffRecordShared/WatchCaptureModels.swift` | `WatchCaptureEnvelope`, `WatchCaptureKind`, `WatchSyncState`, `WatchAudioManifest`, `WatchCaptureSourceSurface`, and queue policy types shared by iPhone tests and watch code. |

### Friday Sub-Models

Friday engine (`FridayAssistantEngine.swift`) maintains four interconnected models:

- **CommunicationStyle** — Vocabulary richness (TTR), directness, formality, signature words
- **EmotionalSignature** — Valence/arousal/dominance baselines, daily/weekly cycles, emotional volatility
- **PersonalKnowledgeGraph** — NER-extracted entities (people, places, orgs) with emotional weights and co-occurrence relationships
- **FridayPredictions** (`FridayPredictions.swift`) — Mood forecasting, trigger anticipation, temporal patterns, seasonal detection

### Views

| View | File | Purpose |
|---|---|---|
| **ContentView** | `ContentView.swift` | Main TabView container. Adapts to sidebar on iPadOS 18+. |
| **TodayView** | `TodayView.swift` | Daily journaling interface with recording |
| **TimelineView** | `TimelineView.swift` | Historical entry browsing and hybrid semantic search results |
| **FridayView** | `FridayView.swift` | Friday personality display and insights |
| **FridayChatView** | `FridayChatView.swift` | "Talk to Friday" conversational interface, free-form questions, and evidence chips |
| **EntryDetailView** | `EntryDetailView.swift` | Entry viewing and editing |
| **InsightsView** | `StatsView.swift` | Mood trends, streaks, analytics |
| **WeeklyReflectionViews** | `WeeklyReflectionViews.swift` | Home card, report detail, history rows, source sheet, takeaway save, export sheet, and report-level actions |
| **SettingsView** | `SettingsView.swift` | Preferences, configuration, Weekly Reflection settings, Semantic Memory controls, and Siri & System Search metadata controls |
| **OnboardingView** | `OnboardingView.swift` | First-launch setup flow |
| **BackupExportView** | `BackupExportView.swift` | Export and import data |

### Support Modules

| Module | File | Purpose |
|---|---|---|
| **EncryptionService** | `EncryptionService.swift` | AES-256-GCM via CryptoKit. File format: `[DVX1 magic][salt][nonce][ciphertext+tag]` |
| **AppLockManager** | `AppLockManager.swift` | Face ID / Touch ID via LocalAuthentication |
| **ThemeManager** | `ThemeManager.swift` | 8 themes (System, Light, Sage, Lavender, Rose, Ocean, Warm, Dark) |
| **PhotoStorageManager** | `PhotoStorageManager.swift` | On-device photo attachment storage (up to 5 per entry) |
| **GoalManager** | `GoalManager.swift` | Journaling goals, streaks, milestones |
| **ReviewManager** | `ReviewManager.swift` | App Store review prompts via SKStoreReviewController |
| **BackupService** | `BackupService.swift` | Export/import orchestration |
| **PDFExportService** | `PDFExportService.swift` | PDF generation from entries |
| **HapticManager** | `HapticManager.swift` | Haptic feedback patterns |
| **ReminderManager** | `ReminderManager.swift` | Daily reminder notifications |
| **WeeklyReflectionNotificationScheduler** | `WeeklyReflectionServices.swift` | Weekly local notification request with static privacy-safe content and recurring calendar trigger |
| **AppIntents** | `AppIntents.swift` | App Intents, App Shortcuts, Siri, Shortcuts, Action Button, and safe journal entity discovery |

### System Discoverability

OffRecord exposes a privacy-safe system surface without making raw journal content searchable outside the authenticated app:

- **App Intents and App Shortcuts**: Record Journal, Write Entry, Search Journal, Set Mood, Ask Friday, Open Today, Open Entry, and Star Entry.
- **JournalEntryEntity**: An `AppEntity`/`IndexedEntity` wrapper around `DiaryEntry` that exposes safe metadata only: id, date, mood, word count, starred state, voice note presence, photo presence, and updated date.
- **Core Spotlight**: `JournalSpotlightIndexer` uses domain `journalEntries` and stable identifiers shaped as `entry:<uuid>`. It indexes started entries only.
- **Deep links and routing**: `OffRecordNavigationRouter` handles `offrecord://today`, `offrecord://record`, `offrecord://timeline?query=...`, `offrecord://entry/{uuid}`, `offrecord://friday?question=...`, `offrecord://weekly-reflection/current`, and `offrecord://weekly-reflection/{reportID}`, including queued routes while onboarding or app lock blocks navigation.
- **NSUserActivity**: Entry detail can be eligible for search and prediction; Today, Timeline search, and Friday surfaces donate prediction-only activities.
- **Settings controls**: The “Siri & System Search” section includes “Show entries in Spotlight” and “Rebuild Spotlight Metadata”. Disabling Spotlight metadata removes the app's Spotlight domain.

System-facing metadata must never include raw journal text, transcript snippets, generated semantic chunks, photo thumbnails, or audio filenames.

### Apple Watch Surfaces

- **Watch app**: Quick Capture Home, Mood, Speak, Record, and Recent. Recent is an outbox/status view, not a journal archive.
- **Mood**: Crown-first dial over the same eight moods used by iPhone.
- **Speak**: Dictation-oriented text capture. Only saves `Transcript on watch now` when dictated text exists.
- **Record**: Audio-first recording with pause/resume, soft 5-minute warning, hard 10-minute cap, interruption handling, and audio session deactivation after stop.
- **Complication / Smart Stack**: Generic Quick Capture launch and queue status only. No journal text, transcript, mood details beyond generic status, audio filenames, or content snippets.

### Core Data Watch Additions

- `AudioAttachment` stores multiple audio notes for one `DiaryEntry`, including `fileName`, `duration`, `createdAt`, optional `sourceCaptureID`, byte count, and codec.
- `DiaryEntry.audioFileName` and `DiaryEntry.duration` remain compatibility fields for legacy single-audio surfaces while newer playback and backup paths read the attachment relationship.
- `WatchImportReceipt` stores imported `captureID`, target entry ID, import timestamp, kind, and hash. It is local-only and not CloudKit-synced.
- Backup/export includes `AudioAttachment` records so multiple watch recordings survive JSON and encrypted backup round trips.

## Apple Frameworks Used

| Framework | Purpose |
|---|---|
| Speech | On-device speech recognition |
| NaturalLanguage | NLP (sentiment, NER, POS tagging, contextual embeddings) |
| Accelerate | Vector normalization and similarity math |
| SQLite3 / FTS5 | Durable local lexical sidecar for hybrid search |
| CoreData | Local persistence |
| CloudKit | Optional iCloud sync |
| CryptoKit | AES-256-GCM encryption |
| LocalAuthentication | Biometric security |
| WidgetKit | Home & Lock Screen widgets |
| UserNotifications | Daily reminders and static Weekly Reflection reminders |
| WatchConnectivity | Durable metadata and audio file transfer between Apple Watch and iPhone |
| AppIntents | App Intents, App Shortcuts, Siri, Shortcuts, Control Center, Action Button |
| CoreSpotlight | Private metadata-only entry indexing and Spotlight result routing |
| AVFoundation | Audio recording & playback |
| FoundationModels | Optional iOS 26 Apple Intelligence responder for richer Friday phrasing after evidence retrieval |

## Key Constraints

- **Zero external dependencies** — No third-party SDKs, analytics, crash reporting, or ad networks
- **Local journal intelligence** — Friday insights, Semantic Memory, and mood analysis stay on the device; Apple Speech transcription is disclosed and permission-based
- **No network calls** for user data — Optional iCloud sync is user-initiated and Apple-encrypted
- **Local semantic sidecar** — Embeddings, vector blobs, and lexical index rows are derived locally, rebuildable, and not CloudKit-synced
- **Weekly Reflection local reports** — Generated reports, evidence refs, saved takeaways, hidden source IDs, and settings are local Codable AI state; source hiding is report/version scoped and does not mutate entries
- **Weekly notification privacy** — Weekly Reflection notification title, body, and userInfo must remain static and free of journal-derived text
- **Private system indexing** — Spotlight and App Entity metadata must not contain raw journal text, transcripts, generated semantic chunks, photo thumbnails, or audio filenames
- **Watch privacy** — Watch complications, Smart Stack widgets, notifications, and Recent with previews disabled must not expose journal text, transcript snippets, or audio filenames
- **Watch import integrity** — Audio watch captures require file delivery before receipt creation; replayed transfers must be idempotent by `captureID`
- **Evidence-first Friday** — Substantive Friday claims must cite retrieved `EvidenceReference` values or hedge/refuse
- **Optional Foundation Models** — Availability-gated phrasing only; retrieved journal evidence remains the source of truth
- **Privacy label** — Apple "Data Not Collected"

For canonical feature designs, see [SEMANTIC_MEMORY_FRIDAY.md](SEMANTIC_MEMORY_FRIDAY.md) and [WEEKLY_REFLECTION.md](WEEKLY_REFLECTION.md).

## Building

1. Open `OffRecord/OffRecord.xcodeproj` in Xcode 15+
2. Select the `OffRecord` scheme
3. Build and run on an iOS 17+ Simulator or device
4. Tests: `OffRecordTests` (unit) and `OffRecordUITests` (UI)

Apple Watch support requires the watchOS 26.2 platform/runtime installed from Xcode Settings > Components for full embedded app and simulator builds. Without that runtime, source typechecks may pass while full `OffRecord` or `OffRecordWatch` builds fail during watch content compilation/thinning.
