# Changelog

All notable changes to OffRecord AI Journal are documented here.

## [1.3.0] — Unreleased

### Added
- **Semantic Memory Search**: Timeline search now finds entries by meaning while preserving exact people, places, topics, mood, date, recency, and starred-entry ranking.
- **Evidence-Based Friday**: Free-form Friday answers retrieve journal evidence first, cite source entries, and refuse unsupported questions instead of guessing.
- **Semantic Memory Controls**: Settings now shows index status and supports rebuilding or deleting the local-only semantic index.

### Privacy
- Semantic embeddings, chunk metadata, and lexical index data are local-only derived data. They are rebuildable per device and are not synced through CloudKit.

### QA
- Added deterministic unit and UI coverage for chunking, hybrid ranking, index lifecycle, typed search states, citations, refusal paths, and evidence deep links.

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
- Voice journaling with fully on-device transcription (Apple Speech framework)
- Friday: on-device personality model (communication style, emotional signature, knowledge graph)
- Mood tracking with automatic sentiment analysis (NLTagger)
- Smart insights and pattern detection
- Biometric security (Face ID / Touch ID)
- Photo attachments (up to 5 per entry)
- 8 themes (System, Light, Sage, Lavender, Rose, Ocean, Warm, Dark)
- Encrypted exports (PDF, JSON, Markdown, CSV, AES-256-GCM backup)
- Optional iCloud sync
- Home Screen & Lock Screen widgets
- Siri Shortcuts via AppIntents
- Journaling goals with weekly targets and milestone celebrations
- Full iPad support with adaptive layouts
