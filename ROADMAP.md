# OffRecord AI Journal Roadmap

What has shipped, what is left, and what is not planned. Contributions are welcome: check [open issues](https://github.com/Saransh-Sharma/Off-Record/issues) or propose your own.

Three rules hold for everything below:

- Journal text, embeddings, Friday prompts, and retrieved evidence never go to a server. The language model is Apple's on-device `SystemLanguageModel`, never Private Cloud Compute.
- Friday makes no claim without entries to cite, and says so when the journal doesn't support an answer.
- High-risk content gets support, never analysis or quotes.

## Shipped

### v1.0 — Core Voice Journal
- Voice journaling with Apple Speech transcription after explicit consent
- Friday personality model (communication style, emotional signature, knowledge graph)
- NLP analysis via NLTagger (sentiment, named entities, topics)
- Core Data storage with optional iCloud sync
- Biometric security (Face ID / Touch ID)
- Widgets (Home Screen & Lock Screen)
- Basic Siri shortcut support through App Intents
- AES-256-GCM encrypted exports
- 8 themes, photo attachments, journaling goals

### v1.1 — Friday Predictions
- Friday Predictions: mood forecasting, trigger anticipation, temporal patterns
- Shareable Personality Card for social media
- Weekly Insight Cards
- Improved NLP keyword extraction

### v1.2 — Talk to Friday
- Talk to Friday: conversational chat with your Friday
- Shareable Personality Cards (Instagram Stories + Twitter/X formats)
- Smarter App Store review prompts

### v1.3 — Search by Meaning + Evidence-Based Friday
- Timeline search by meaning using Apple NaturalLanguage embeddings and word matching on the device
- Hybrid ranking for meaning matches, exact people/places/topics, recency, starred entries, mood filters, and date filters
- Evidence-Based Friday answers that retrieve journal evidence first and cite source entries
- Deterministic Friday fallback that hedges or refuses when evidence is missing, weak, contradictory, unavailable, or still indexing
- A search index kept on the device, with Settings controls for rebuild and delete
- Background index lifecycle for first build, incremental entry updates, deletes, and CloudKit reconciliation
- Optional Foundation Models phrasing layer where available; retrieved evidence remains the source of truth
- Privacy-safe system discoverability through App Shortcuts, Siri, Spotlight metadata, Action Button-ready shortcuts, widget links, `NSUserActivity`, and `offrecord://` deep links
- “Siri & System Search” Settings controls for Spotlight metadata visibility and rebuilds

### v1.4 — Weekly Reflection + Apple Watch Quick Capture
- Weekly Reflection with Home card, report detail, Insights history, saved takeaways, source controls, regeneration, export, Settings controls, and local notifications
- Deterministic weekly reports from started entries, mood, sentiment, source type, topics, and snippets
- Report-level source hiding and re-inclusion with versioned regeneration
- High-risk entries count for eligibility/source management but stay out of generated insights, quotes, and exports
- watchOS 26+ companion for Mood, Speak, Record, and Recent, with privacy-safe complication and Smart Stack entry points
- Durable WatchConnectivity sync with metadata transfer, audio file transfer, retry/backoff state, iPhone receipts, and idempotent imports
- Multiple `AudioAttachment` recordings per day, kept in JSON and encrypted backups

### v1.5 — Private by Default, Friday On-Device, Mac
**Safety and trust**
- One safety check (`JournalRiskClassifier`) on every AI surface. Self-harm and suicide content gets one supportive line and the Get Support sheet, never analysis or quotes.
- Get Support sheet with the region's crisis line, emergency number, Message Someone You Trust, and Find a Helpline. It works offline.
- Friday is labeled as an AI in onboarding and the chat header.
- Friday's profile is rebuilt from your entries whenever the journal changes, and Settings has Rebuild Friday.
- Friday's profile, chat, memory edits, generated titles, and Go Deeper questions live in a local folder that never syncs and is excluded from device backups.

**Privacy controls**
- Keep Out of Friday on any entry, with an optional Skip Weekly Reflection.
- The Friday switch. Turning Friday off deletes what she learned and said.
- Erase All Data. With iCloud Sync on, the deletion reaches iCloud too.
- Backups keep Keep Out of Friday, tags, and journal membership.

**Friday on Apple's on-device model**
- Multi-turn chat that looks things up with three journal tools (search, mood counts, people) and cites only what they returned.
- Short generated titles for entries, Go Deeper questions written for the entry, and rephrased Weekly Reflection cover lines and summaries.
- Every generated line passes the voice and safety checks or falls back to deterministic wording. Grounding goldens run through Apple's Evaluations on iOS 27.
- One shared sentiment and name engine replaces five older copies.
- Proactive cards for patterns, resurfaced topics, and decision and regret follow-ups; Smart Prompts from Friday; and a “Why?” sheet for every insight.

**Looking back**
- Month in Review and Year in Review, with a shareable year card that hides names by default.
- Session Prep: a summary of a date range for a session with a therapist or coach, exported as PDF, Markdown, or plain text.
- Forgiving streaks: one rest day in any 7 days, or weekly streaks, with the same number in the app and the widgets.

**Organizing**
- Tags: add on an entry, filter Timeline, search with `#`, and rename, merge, or delete in Settings.
- Multiple journals, each with its own entry per day, a journal picker for capture and Timeline, and PDF export of one journal.
- A page for each person, place, and topic in My World.
- Import from Day One, Apple Journal, Markdown or text files, and CSV, with a preview and no duplicates on re-import.

**Siri and system**
- Create Entry, Create Audio Entry, and Search adopt Apple's journal schemas; the entry entity carries no text.
- Ask Friday answers inside Siri with a summary only, and Siri knows which entry is on screen.
- Journaling Suggestions on iPhone start an entry from Apple's suggestions.

**Sync and platforms**
- iCloud sync status in Settings, and turning sync on or off applies without a relaunch.
- A recovery screen when the journal can't open: Try Again, Export a Copy, and Contact Support. Nothing is deleted.
- Recordings from another device say where they were made and where to play them.
- Mac app through Mac Catalyst, with a sidebar and menu commands. This replaces the earlier plan for a separate native macOS target.

**Design and copy**
- Liquid Glass tab bar with a Record bar, a new capture sheet, Timeline List, Calendar, and Photos views, Swift Charts on Insights, dark mode, and a Record control for Control Center and the Lock Screen.
- Every screen, widget, watch face, Siri phrase, and export rewritten to one copy standard, checked by `scripts/copy-lint.sh`.
- Dynamic Type, 44pt tap targets, chart summaries for VoiceOver, and Reduce Motion everywhere.

## Next

### Device QA
These need real hardware:
- **Siri:** Ask Friday answers after Face ID and its Open in Friday button works; a heavy question opens Get Support over the Lock Screen.
- **Journaling Suggestions:** the picker on iPhone starts an entry and attaches photos, up to 5.
- **iCloud:** turning Sync on and off with a real account; a second device sees entries, tags, and journals after the CloudKit schema for model version 3 is deployed.
- **Mac app:** visual QA of the sidebar, menu commands (⌘N, ⇧⌘R, ⌘F, ⌘,), and Settings.
- **Apple Watch:** paired-device QA for the offline queue, reconnect, duplicate deliveries, long audio, interruptions, privacy previews, Reduce Motion, and large text; captures land in the main journal.
- **On-device model quality** on an Apple Intelligence device: chat tools, titles, Go Deeper, and Weekly Reflection wording.

### Localization
- Spanish: in progress, needs native review. No multi-language claim until a locale is complete and reviewed.

### Open ideas
- Monthly self-knowledge: a few “You tend to…” lines in Month in Review, each linked to the entries behind it.
- Change over time: compare months to show how moods and themes shifted, with sources.
- Export what Friday learned (knowledge graph and emotional patterns) in an open format.

## Not Planned

- **LoRA fine-tuning (a personal adapter trained on Mac):** it would mean exporting journal text for training and shipping a large adapter, and the on-device model with journal tools already grounds Friday in your entries.
- **Friday in your voice (Personal Voice):** Friday is labeled as an AI, and speaking in your own voice would blur that.
- **“How would I react?” predictions:** predicting your behavior from old entries invites false certainty; Friday answers only from what your entries say.
- **Big Five personality scores and psychometric prompt conditioning:** trait scores from journal text can't be checked for one person, and Friday makes no clinical claims.

---

For technical details, see [ARCHITECTURE.md](ARCHITECTURE.md), [SEMANTIC_MEMORY_FRIDAY.md](SEMANTIC_MEMORY_FRIDAY.md), [WEEKLY_REFLECTION.md](WEEKLY_REFLECTION.md), and the [Technology page](https://saransh-sharma.github.io/Off-Record/technology.html).
