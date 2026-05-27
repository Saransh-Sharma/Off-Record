# Changelog

All notable changes to OffRecord AI Journal are documented here.

## [1.4.0] — Unreleased

### Added
- **Proactive Weekly Reflection**: Added a local weekly report with Home card, report detail, Insights history, saved takeaways, source controls, regeneration, export, and Settings controls.
- **Weekly Reflection Notifications**: Added recurring local weekly reminders with static privacy-safe copy and deep-link routing to the current report.
- **Apple Watch Quick Capture**: Added a watchOS 26+ companion for Mood, Speak, Record, and Recent capture flows. The watch app is capture/outbox only; the iPhone remains the canonical journal.
- **Privacy-Safe Watch Complication and Smart Stack**: Added generic Quick Capture launch surfaces and queue status without journal text, transcripts, audio filenames, or snippets.
- **Durable Watch Sync**: Watch captures are stored locally first, then transferred with WatchConnectivity metadata and audio file transfers. The outbox persists retry state, backoff timing, missing-file status, and receipt handling.
- **Multi-Audio Attachments**: Added `AudioAttachment` records so multiple watch recordings on the same day are preserved while keeping legacy `audioFileName` compatibility.
- **Watch Import Receipts**: Added local-only `WatchImportReceipt` idempotency so duplicate WatchConnectivity deliveries do not duplicate journal content.
- **Audio Attachment Backup Support**: JSON and encrypted backups now include multiple audio attachment records.

### Privacy
- Weekly Reflection generation is deterministic and local-only. Reports are persisted as Codable AI state and are not sent to developer servers or non-Apple AI services.
- High-risk entries count toward weekly eligibility and source management but are excluded from generated insights, evidence quotes, source snippets, and exports.
- Weekly Reflection notification title, body, and route payload stay journal-free.
- Watch complications, Smart Stack widgets, and Recent with previews disabled remain privacy-safe and do not expose raw journal text.
- Watch audio imports are file-first: metadata alone cannot create a completed imported audio entry or synced receipt.
- No analytics, tracking, telemetry SDKs, developer servers, or non-Apple AI services were added for watch support.

### QA
- Added Weekly Reflection coverage for eligibility thresholds, report versioning, dismiss/delete visibility, high-risk exclusion, source re-inclusion, notification privacy, export quote defaults, Home states, source sheet flows, and current deep-link version behavior.
- Added Watch Quick Capture coverage for 20-item Recent projection, retry backoff, duplicate import replay, missing audio metadata, duplicate audio delivery, and backup round trips.
- Full embedded watch app and watch simulator builds require installing the watchOS 26.2 platform/runtime in Xcode.

## [1.3.0] — Unreleased

### Added
- **Semantic Memory Search**: Timeline search now finds entries by meaning while preserving exact people, places, topics, mood, date, recency, and starred-entry ranking.
- **Evidence-Based Friday**: Free-form Friday answers retrieve journal evidence first, cite source entries, and refuse unsupported questions instead of guessing.
- **Semantic Memory Controls**: Settings now shows index status and supports rebuilding or deleting the local-only semantic index.
- **System Discoverability**: Added privacy-safe App Intents, App Shortcuts, Spotlight entry metadata, Siri and Action Button readiness, widgets links, `NSUserActivity` donation, and deep-link routing for Today, recording, Timeline search, entry detail, and Friday questions.
- **Siri & System Search Settings**: Added controls to show entries in Spotlight, rebuild Spotlight metadata, and open Shortcuts setup from Settings.

### Privacy
- Semantic embeddings, chunk metadata, and lexical index data are local-only derived data. They are rebuildable per device and are not synced through CloudKit.
- Spotlight and App Entity indexing expose private metadata only: date, mood, starred state, word count, and voice/photo presence. Raw journal text, transcripts, generated semantic chunks, photo thumbnails, and audio filenames are not indexed by system search.

### QA
- Added deterministic unit and UI coverage for chunking, hybrid ranking, index lifecycle, typed search states, citations, refusal paths, and evidence deep links.
- Added coverage for Spotlight metadata redaction, empty-draft exclusion, stable Spotlight identifiers, deep-link route parsing, safe entity display text, and Settings discoverability controls.

## [1.2.0] — 2026-05-11

### Added
- **Talk to Friday**: Chat with your Friday — ask about mood patterns, personality, journaling habits
- **Shareable Personality Cards**: Beautiful cards optimized for Instagram Stories (1080x1920) and Twitter/X (1200x675)
- **Smarter Review Prompts**: Milestone-based App Store rating requests (at 5, 15, 40 entries) with 90-day cooldown

## [1.1.0] — 2026-03-26

### Added
- **Friday Predictions**: Mood forecasting, trigger anticipation, temporal pattern detection
- **Shareable Personality Card**: Visual snapshot of your Friday profile
- **Weekly Insight Cards**: Shareable summaries of your weekly emotional journey
- **Improved NLP**: Better keyword extraction with refined text processing

## [1.0.0] — 2026-03-23

### Added
- Voice journaling with Apple Speech transcription after explicit consent
- Friday: on-device personality model (communication style, emotional signature, knowledge graph)
- Mood tracking with automatic sentiment analysis (NLTagger)
- Smart insights and pattern detection
- Biometric security (Face ID / Touch ID)
- Photo attachments (up to 5 per entry)
- 8 themes (System, Light, Sage, Lavender, Rose, Ocean, Warm, Dark)
- Encrypted exports (PDF, JSON, Markdown, CSV, AES-256-GCM backup)
- Optional iCloud sync
- Home Screen & Lock Screen widgets
- Basic Siri shortcut support through App Intents
- Journaling goals with weekly targets and milestone celebrations
- Full iPad support with adaptive layouts
