# Changelog

All notable changes to OffRecord AI Journal are documented here.

## [Unreleased]

### Added
- **Native Liquid Glass tab bar** with a Record bar above it on every tab.
- **New capture sheet**: live waveform, optional live transcript, Pause/Resume, Discard, and recording into another day. After saving, a card offers a quick mood pick, Undo, and Open entry.
- **Timeline views**: List, Calendar (month grid and year-in-pixels by mood), and Photos. Swipe to star or delete, context menus with previews, Undo after delete, and "Top Results" for search by meaning.
- **Go Deeper**: an entry can suggest one local follow-up question to write or record about.
- **Friday**: chats are kept on this device between visits, answers cite numbered sources with an evidence-strength label, follow-up questions are suggested, and "What I Remember" supports Forget and Rename.
- **Insights**: Swift Charts mood trends with a range picker, a time-of-day mood heatmap, a "Why?" sheet for every insight, one Weekly Reflection card, and streak milestone celebrations.
- **Widgets and system surfaces**: the iOS widgets now ship in their own extension. New Year in Pixels and tappable mood widgets, a Record control for Control Center and the Lock Screen, and a Live Activity while recording.
- **Settings**: a Privacy card, settings search, and an optional Apple Health State of Mind toggle.
- **Dark mode** across the app; "System" appearance follows the device.
- **Friday on the on-device model:**
  - When Apple Intelligence is available, Friday keeps the chat going across turns.
  - She looks things up in your journal with three tools (search, mood counts, people) and cites only entries those tools returned.
  - Go Deeper can ask a question written for the entry.
  - Entries can get short generated titles, in the entry and on Timeline.
  - Weekly Reflection can rephrase its cover line and summary from the week's facts.
  - All generated text must pass the Voice and safety rules or falls back to the deterministic wording.
  - Without Apple Intelligence, Friday says once that she answers from summaries.
- **Month in Review and Year in Review:**
  - Month in Review appears on Insights, with history.
  - Year in Review opens from December 1 for this year and anytime for past years. It covers counts, Year in Pixels, mood by month, people and topics, and entries that mattered.
  - Its share card replaces names with "someone" unless you turn names on.
  - Links: `offrecord://review/month/2026-09` and `offrecord://review/year/2026`.
- **Session Prep:**
  - Summarizes a date range to bring to a session with a therapist or coach.
  - You choose which quotes to include (none by default) and add "What I Want to Bring Up". Names are replaced unless you turn them on.
  - Exports as PDF, Markdown, or plain text.
- **Import from another app** (Day One JSON, Apple Journal, Markdown or text files, CSV):
  - Shows a preview first.
  - Same-day entries become one day's page.
  - Re-importing doesn't duplicate.
- **Keep Out of Friday:**
  - Per entry, with an optional **Skip Weekly Reflection**.
  - Kept-out entries are never indexed for search by meaning, cited, learned from, or quoted.
  - Weekly Reflection still counts them unless they're skipped too.
- **Friday switch** in Settings. Turning Friday off deletes what she learned, her chat, and generated titles and questions.
- **Erase All Data** in Settings. It deletes the journal, files, indexes, and Friday's data. When iCloud sync is on, the deletion reaches iCloud too, and the confirmation says so.
- **Tags and journals data model** (model version 3). See the organizing features below.
- **Siri and Apple Intelligence:**
  - Create Entry, Create Audio Entry, and Search adopt Apple's journal schemas. The entry entity carries no journal text.
  - Ask Friday answers inside Siri with a summary only, never quotes. Heavy questions open Get Support (`offrecord://support`, which opens even while locked).
  - Siri knows which entry is on screen.
- **Journaling Suggestions** (iPhone): start an entry from Apple's suggestions. Photos attach, up to 5.
- **Forgiving streaks:**
  - Daily streaks allow one rest day in any 7 days.
  - Weekly streaks are available.
  - Widgets show the same number as the app.
  - No loss framing.
- **iCloud Sync status:** the last sync, whether it's syncing now, the last error in plain words, and whether you're signed in to iCloud.
- **iCloud Sync applies right away**; no relaunch.
- **Store recovery screen:** if the journal can't open, you get Try Again, Export a Copy, and Contact Support. Nothing is deleted automatically.
- **Recordings from another device** say where they were made, how long they are, and where to play them.
- **Mac app** (Mac Catalyst):
  - Sidebar, menu commands, and shortcuts (⌘N Write, ⇧⌘R Record, ⌘F Search, ⌘, Settings).
  - No Live Activities, widgets, watch app, Siri tips, or Apple Health on Mac.
  - On iPad, Record moves from ⌘R to ⇧⌘R.

### Safety
- **One safety check for every AI surface.** Friday chat, Go Deeper, proactive cards, Smart Prompts, Weekly Reflection, and Friday's profile check text with `JournalRiskClassifier` (JournalKit). It catches direct and indirect references to suicide or self-harm.
- **Support instead of analysis.** High-risk questions and entries get one supportive line from Friday and a **Get Support** sheet. Friday never retrieves, quotes, or asks about them.
- **Get Support sheet.** It shows the region's crisis line (US, Canada, UK, Ireland, Australia, New Zealand, India) with Call and Text, the emergency number, Message Someone You Trust, and Find a Helpline. It works offline.
- **Fewer probing questions on heavy entries.** Hopeless or heavy entries get no Go Deeper question, no follow-up chips, and no proactive cards.
- **Friday is labeled as an AI.** The chat header reads "AI · On-device", and onboarding adds "Friday is AI".
- **Safety page.** The website explains how OffRecord handles self-harm content.

### Fixed
- **Friday's profile is now rebuilt from your entries** whenever the journal changes:
  - Edits, deletes, imports, Apple Watch captures, and Siri entries now count once.
  - What Friday learned from a deleted entry is gone.
  - It counts entries rather than saves.
  - Settings adds **Rebuild Friday**.

### Changed
- **Requests for App Store reviews** use `AppStore.requestReview(in:)`.
- **One color palette** shared by the app and widgets.
- **Dead code removed:** 27 availability checks below iOS 26.
- **Unit tests use a temporary store** and never write test data to iCloud.
- **Friday's profile no longer syncs through iCloud.** It is rebuilt on each device from your entries and kept in a protected local file.
- **One sentiment and name engine.** It replaces five older copies; `LocalAIEngine` is gone. Sentiment now weighs every paragraph, not just the first.
- **Heavy entries no longer get a question in From Friday.**
- **Backups** keep Keep Out of Friday, tags, and journal membership. Older backups still import.
- **Copy**: every screen, widget, watch face, Siri phrase, and export is rewritten to one standard (see the Voice section of `OffRecord Design.md`): shorter, plain words, one name per thing, privacy stated once where it matters, and Friday speaking in first person. `scripts/copy-lint.sh` checks the mechanical rules.
- Today has a shorter hero with Record, Write, and another prompt, one contextual card (including On This Day), and a calmer streak strip.
- Onboarding is six steps instead of eight; Friday's focus is picked on the intent step.
- The Lock screen asks again when you come back to the app.
- The Watch record screen keeps its header clear of the clock.
- Recording continues in the background so Live Activity controls keep working (`audio` background mode).

### Privacy
- The Diary Entry widget no longer shows journal text on the Home Screen, only mood, word count, voice, and streak.
- Widgets read a small metadata snapshot (dates, moods, counts) instead of opening the journal store.
- Journal content is hidden in the app switcher when the privacy lock is on.
- Shared insight cards replace people's names with "someone" unless you turn names on.
- Friday chat history stays on this device with complete file protection and is excluded from backups.
- Apple Health receives only the mood and time; OffRecord reads nothing from Health.

### Accessibility
- All fonts use Dynamic Type styles; tappable controls meet the 44pt minimum.
- Charts have summaries and audio-graph descriptors; the onboarding button reads its visible title.
- Every animation respects Reduce Motion.

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
