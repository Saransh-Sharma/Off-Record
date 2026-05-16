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

## Module Overview

All source files are in `OffRecord/`.

### Core Pipeline

| Module | File | Responsibility |
|---|---|---|
| **AudioRecorder** | `AudioRecorder.swift` | AVAudioRecorder wrapper. Records AAC at 44.1kHz, provides real-time audio levels. Stores recordings in the app sandbox. |
| **SpeechTranscriber** | `SpeechTranscriber.swift` | Speech-to-text via Apple Speech after explicit consent. Offline-capable paths require on-device recognition when available; online transcription may be processed by Apple Speech. |
| **LocalAIEngine** | `LocalAIEngine.swift` | NLP analysis using NaturalLanguage framework. Sentiment analysis, topic extraction, intent recognition. Maintains a UserProfile for learned patterns. |
| **InsightsEngine** | `InsightsEngine.swift` | Generates insight cards from journal data. Sentiment trends, topic frequency, journaling patterns. |
| **FridayAssistantEngine** | `FridayAssistantEngine.swift` | Core personality model with four sub-models (see below). Processes NLTagger output per entry. Serializes to JSON in Core Data (~12 KB). |
| **Semantic Memory** | `SemanticMemory.swift` | Local-only chunking, embeddings, hybrid search, index lifecycle, and evidence references. |
| **Foundation Models Friday** | `FoundationModelsFridayResponder.swift` | Optional iOS 26 phrasing layer that validates observations against retrieved evidence. |
| **Persistence** | `Persistence.swift` | Core Data with NSPersistentCloudKitContainer. Stores entries, synced photo attachments, audio metadata, and AI state. App Group for WidgetKit data sharing. |
| **System Discoverability** | `AppIntents.swift`, `JournalSpotlightIndexer.swift`, `OffRecordNavigationRouter.swift` | App Shortcuts, privacy-safe `JournalEntryEntity`, Core Spotlight metadata indexing, NSUserActivity prediction/search donation, and `offrecord://` route handling. |

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
| **SettingsView** | `SettingsView.swift` | Preferences, configuration, Semantic Memory controls, and Siri & System Search metadata controls |
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
| **AppIntents** | `AppIntents.swift` | App Intents, App Shortcuts, Siri, Shortcuts, Action Button, and safe journal entity discovery |

### System Discoverability

OffRecord exposes a privacy-safe system surface without making raw journal content searchable outside the authenticated app:

- **App Intents and App Shortcuts**: Record Journal, Write Entry, Search Journal, Set Mood, Ask Friday, Open Today, Open Entry, and Star Entry.
- **JournalEntryEntity**: An `AppEntity`/`IndexedEntity` wrapper around `DiaryEntry` that exposes safe metadata only: id, date, mood, word count, starred state, voice note presence, photo presence, and updated date.
- **Core Spotlight**: `JournalSpotlightIndexer` uses domain `journalEntries` and stable identifiers shaped as `entry:<uuid>`. It indexes started entries only.
- **Deep links and routing**: `OffRecordNavigationRouter` handles `offrecord://today`, `offrecord://record`, `offrecord://timeline?query=...`, `offrecord://entry/{uuid}`, and `offrecord://friday?question=...`, including queued routes while onboarding or app lock blocks navigation.
- **NSUserActivity**: Entry detail can be eligible for search and prediction; Today, Timeline search, and Friday surfaces donate prediction-only activities.
- **Settings controls**: The “Siri & System Search” section includes “Show entries in Spotlight” and “Rebuild Spotlight Metadata”. Disabling Spotlight metadata removes the app's Spotlight domain.

System-facing metadata must never include raw journal text, transcript snippets, generated semantic chunks, photo thumbnails, or audio filenames.

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
| AppIntents | App Intents, App Shortcuts, Siri, Shortcuts, Control Center, Action Button |
| CoreSpotlight | Private metadata-only entry indexing and Spotlight result routing |
| AVFoundation | Audio recording & playback |
| FoundationModels | Optional iOS 26 Apple Intelligence responder for richer Friday phrasing after evidence retrieval |

## Key Constraints

- **Zero external dependencies** — No third-party SDKs, analytics, crash reporting, or ad networks
- **Local journal intelligence** — Friday insights, Semantic Memory, and mood analysis stay on the device; Apple Speech transcription is disclosed and permission-based
- **No network calls** for user data — Optional iCloud sync is user-initiated and Apple-encrypted
- **Local semantic sidecar** — Embeddings, vector blobs, and lexical index rows are derived locally, rebuildable, and not CloudKit-synced
- **Private system indexing** — Spotlight and App Entity metadata must not contain raw journal text, transcripts, generated semantic chunks, photo thumbnails, or audio filenames
- **Evidence-first Friday** — Substantive Friday claims must cite retrieved `EvidenceReference` values or hedge/refuse
- **Optional Foundation Models** — Availability-gated phrasing only; retrieved journal evidence remains the source of truth
- **Privacy label** — Apple "Data Not Collected"

For the canonical feature design, see [SEMANTIC_MEMORY_FRIDAY.md](SEMANTIC_MEMORY_FRIDAY.md).

## Building

1. Open `OffRecord/OffRecord.xcodeproj` in Xcode 15+
2. Select the `OffRecord` scheme
3. Build and run on an iOS 17+ Simulator or device
4. Tests: `OffRecordTests` (unit) and `OffRecordUITests` (UI)
