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

Since OffRecord AI Journal processes all data on-device with no network calls, the primary security concerns are:

- Local data encryption and storage
- App lock / biometric authentication bypass
- Export/backup data leakage
- Semantic Memory sidecar leakage or stale derived data
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
- Apple embedding asset downloads may fetch model files only; journal text, snippets, embeddings, and Friday questions must not be sent to developer servers or third-party APIs.

Please report any issue where the semantic sidecar stores unexpected plaintext, survives delete-index controls, syncs outside the device-local path, bypasses app lock expectations, or transmits journal-derived data.

For the full feature architecture and privacy model, see [SEMANTIC_MEMORY_FRIDAY.md](SEMANTIC_MEMORY_FRIDAY.md).
