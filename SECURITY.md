# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in OffRecord AI Journal, please report it responsibly.

**Do NOT open a public issue for security vulnerabilities.**

Instead, email **intrepidkarthi@gmail.com** with:

- A description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

You can expect an initial response within 72 hours. We will work with you to understand the issue and coordinate a fix before any public disclosure.

## Supported Versions

| Version | Supported |
| ------- | --------- |
| Latest  | Yes       |

## Scope

Since OffRecord AI Journal keeps journal intelligence local and only uses Apple Speech for transcription after permission, the primary security concerns are:

- Local data encryption and storage
- App lock / biometric authentication bypass
- Export/backup data leakage
- Semantic Memory sidecar leakage or stale derived data
- Weekly Reflection report, evidence, source quote, or export leakage
- Any unintended data transmission

## Semantic Memory Index

Semantic Memory Search and Evidence-Based Friday use a local derived index built from journal entries. This sidecar is sensitive because embeddings, vector blobs, chunk metadata, and lexical search rows can reveal information about journal content even when they are not full entries.

Security expectations:

- The semantic index stays in the local app container and is not synced through CloudKit.
- Journal entries remain in Core Data with optional user-controlled iCloud sync; derived embeddings and FTS rows are rebuilt per device.
- The lexical sidecar should avoid unintended full-plaintext persistence when offsets can recover snippets from Core Data.
- Embeddings and tokenized lexical rows must be treated as sensitive derived journal data, not anonymous telemetry.
- File protection should remain aligned with the rest of OffRecord's local journal-derived storage.
- Settings must allow users to delete and rebuild the local semantic index without deleting entries, photos, audio, exports, widgets, or iCloud data.
- Apple embedding asset downloads may fetch model files only; journal text, snippets, embeddings, and Friday questions must not be sent to developer servers or non-Apple third-party APIs.
- Apple Speech transcription must remain gated by explicit consent before any online speech recognition path can run.

Please report any issue where the semantic sidecar stores unexpected plaintext, survives delete-index controls, syncs outside the device-local path, bypasses app lock expectations, or transmits journal-derived data.

## Weekly Reflection Reports

Weekly Reflection reports are local derived journal data. They can contain summaries, themes, evidence references, saved takeaways, hidden source IDs, source dates, source types, and optionally source quotes during export.

Security expectations:

- Weekly Reflection reports stay local in existing AI state and are not sent to developer servers or non-Apple third-party APIs.
- Report payloads, evidence refs, saved takeaways, and hidden source IDs must be treated as sensitive journal-derived data.
- Source hiding is scoped to a report version and must not mutate original entries or create global entry privacy flags.
- High-risk entries may count for weekly eligibility and source management, but their text, snippets, topics, quotes, and evidence refs must not appear in generated insight fields or exports.
- Weekly Reflection notification content and payloads must remain static and journal-free.
- Export keeps quotes off by default, and high-risk quotes must never be exported even when quote export is enabled.
- Deep-link routing to Weekly Reflection must respect onboarding and app lock deferral before private content is shown.

Please report any issue where Weekly Reflection exposes journal-derived content in notifications, leaks hidden or high-risk source text, persists report data outside the local AI state path, bypasses app lock expectations, or exports quotes without explicit user action.

For the full feature architecture and privacy model, see [SEMANTIC_MEMORY_FRIDAY.md](SEMANTIC_MEMORY_FRIDAY.md) and [WEEKLY_REFLECTION.md](WEEKLY_REFLECTION.md).
