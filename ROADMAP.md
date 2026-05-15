# OffRecord AI Journal Roadmap

This roadmap outlines the planned evolution of OffRecord AI Journal. Contributions are welcome for any upcoming version — check [open issues]() or propose your own.

## Shipped

### v1.0 — Core Voice Journal
- Voice journaling with fully on-device transcription (SFSpeechRecognizer)
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

### v1.3 — Semantic Memory Search + Evidence-Based Friday *(current)*
- Timeline semantic search using local Apple NaturalLanguage embeddings and lexical matching
- Hybrid ranking for meaning matches, exact people/places/topics, recency, starred entries, mood filters, and date filters
- Evidence-Based Friday answers that retrieve journal evidence first and cite source entries
- Deterministic Friday fallback that hedges or refuses when evidence is missing, weak, contradictory, unavailable, or still indexing
- Local-only semantic index sidecar with Settings controls for rebuild and delete
- Background index lifecycle for first build, incremental entry updates, deletes, and CloudKit reconciliation
- Optional iOS 26 Foundation Models phrasing layer where available; retrieved evidence remains the source of truth
- Privacy-safe system discoverability through App Shortcuts, Siri, Spotlight metadata, Action Button-ready shortcuts, widgets links, `NSUserActivity`, and `offrecord://` deep links
- “Siri & System Search” Settings controls for Spotlight metadata visibility and rebuilds
- Automated and manual QA coverage for chunking, ranking, typed states, index lifecycle, and Friday citation behavior

## Planned

### v1.4 — Friday Proactive Reflection + Semantic Intelligence Polish
- Proactive Friday cards that surface unusual entries, theme shifts, weekly recaps, and decision/regret follow-ups
- "Themes taking shape" insight from repeated topics and entities across recent entries, always with source evidence
- Context-aware Today prompts that appear only when they can help the next reflection
- Privacy-safe Friday smart reminders that never expose names, places, snippets, or sensitive content on the Lock Screen
- Decision follow-up loop: detect patterns like "I decided to...", "I regret...", and "I chose...", then let users mark them reflected
- Evidence-first framing for proactive insights: every card explains why it appeared and links back to supporting entries
- Optional String Catalog groundwork for new or changed v1.4 copy; no full multi-language claim until at least one locale is complete and QA'd

### v1.5 — Apple Watch Companion
- Apple Watch companion app (WatchKit) for voice mood check-ins
- WatchConnectivity for iPhone-Watch sync
- Watch Complications for quick access

### v1.6 — Native macOS
- Native macOS target using the shared SwiftUI codebase
- Sidebar navigation and desktop-optimized Timeline, Friday, and Settings surfaces
- Friday accessible from the desktop, with the same local-only evidence rules

### v2.0 — Optional Foundation Models Enhancements *(iOS 26, Apple Intelligence-capable devices)*
- Deeper Apple Foundation Models integration where `SystemLanguageModel.default.availability` allows it
- LanguageModelSession for richer multi-turn wording after evidence retrieval
- Tool calling experiments that query local app data through explicit, evidence-preserving tools
- @Generable for type-safe structured outputs that map observations to retrieved evidence IDs
- Multi-tier personality conditioning for Friday conversations (demographic + behavioral + psychometric prompts, informed by recent persona-modeling research)
- "How would I react?" — Friday predicts your response to situations based on past patterns and personality
- Friday replies in your voice using Apple Personal Voice API (AVSpeechSynthesizer)
- Autobiographical memory consolidation: monthly distillation of journal entries into semantic self-knowledge ("I tend to...", "I always...")
- SpeechAnalyzer replaces SFSpeechRecognizer
- Zero network calls for journal text, embeddings, Friday prompts, or retrieved evidence

### v2.5 — LoRA Fine-Tuning
- Personal LoRA adapter training on Mac (macOS app becomes the training environment)
- ~160 MB adapter delivered via Background Assets
- Train Friday to sound and think like you
- Export entries as JSONL for training
- Validated Big Five personality scoring from journal narratives (Openness, Conscientiousness, Extraversion, Agreeableness, Neuroticism)
- Scientific personality profile based on [language-based personality modeling research](https://arxiv.org/abs/2506.19258)
- Identity evolution tracking: diff monthly personality snapshots to show how you've changed over time

### v3.0 — True Private Assistant *(vision)*

The goal of v3.0 is a private assistant with deep understanding of your journaling patterns — one that remembers what you've shared, sees patterns you might miss, and can respond in your voice. Entirely on-device, entirely yours.

**What Friday can do at v3.0:**

- Talk like you — your vocabulary, phrasing, tone, and reasoning patterns
- Sound like you — replies spoken with Apple Personal Voice (Personal Voice)
- Know what you care about — values, people, topics, ranked by emotional weight
- Know how you've felt across years — full emotional history with temporal patterns
- Predict your likely reaction to familiar situations — grounded in your actual past decisions
- Explain why you feel the way you do — causal reasoning citing specific past entries
- Show how you've changed over time — personality evolution across months and years

**What Friday cannot do (and why):**

- Replace you in a conversation — it knows your narrated self, not your complete self. The thoughts you don't journal are invisible to it
- Handle truly novel situations — it extrapolates from personality traits, but humans are inconsistent and surprise even themselves
- Feel what you feel — no embodied experience (fatigue, hunger, physical state) or subconscious drives

**The honest framing:** This is not a replacement for you. It is a private assistant that gets more useful every day you journal. After years of daily entries, it becomes something no one else has — a private, evolving, on-device record of who you are and who you've been.

**Technical capabilities:**

- Full RAG implementation with personal knowledge base
- Personal LoRA adapter loaded at runtime
- Autonomous tool calling for data access
- Context condensation for long conversations
- Full causal reasoning: "Why did I feel this way?" with cited evidence from past entries
- Exportable private assistant archive — your Friday's personality model, knowledge graph, emotional history, and voice in an open format

---

For technical details, see [ARCHITECTURE.md](ARCHITECTURE.md), [SEMANTIC_MEMORY_FRIDAY.md](SEMANTIC_MEMORY_FRIDAY.md), and the [Technology page](https://offrecord.example.com/technology.html).
