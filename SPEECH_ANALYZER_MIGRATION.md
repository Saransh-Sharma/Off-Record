# SpeechAnalyzer Migration

## Shipping architecture

All production transcription now runs through Apple’s iOS 26 `SpeechAnalyzer`.

- Saved recordings prefer `SpeechTranscriber`; `DictationTranscriber` is the locale-coverage fallback.
- Live voice search uses the same module selection, asset manager, audio conversion, and finalization policy.
- Apple Watch remains a capture/transfer client. The paired iPhone analyzes transferred recordings.
- There is no `SFSpeechRecognizer`, network recognition, or server-transcription fallback.
- OffRecord’s minimum iOS version is 26. JournalKit remains iOS 17-compatible because its non-speech products are shared; analyzer APIs are availability-gated.

## Model assets

`TranscriptionAssetManager` owns model lifecycle:

- resolves an equivalent supported locale;
- serializes duplicate downloads into one installation task;
- exposes download progress;
- verifies the installed state after download;
- reserves the selected locale while transcription is enabled;
- releases reservations when the user disables transcription.

An unavailable model or unsupported locale never blocks saving audio. The attachment records a retryable failure state.

## Persistence migration

`OffRecord 2.xcdatamodel` adds optional/defaulted fields to `AudioAttachment`:

- `transcriptionStatus`
- `transcriptionAttemptCount`
- `transcriptionEngine`
- `transcriptionLocale`
- `transcriptionErrorCode`
- `transcriptionUpdatedAt`
- `transcriptBlockID`

The original model is unchanged. Automatic lightweight migration is enabled, and the new model is selected through `.xccurrentversion`.

Transcript writes are attachment-scoped. A retry updates the text block referenced by `transcriptBlockID` (or its attachment/capture identifier) rather than appending duplicate text. App code passes `NSManagedObjectID` across asynchronous boundaries and refetches objects on the view context.

## Release gates

Before TestFlight:

1. Install the last production build on a physical device and create text, iPhone audio, and Watch audio entries.
2. Install the migrated build over it.
3. Verify existing entries/audio open, one new transcript block is created per attachment, and a retry updates that block.
4. Test first-use model download, download cancellation, airplane mode with an installed model, unsupported locale, microphone denial, and consent revocation.
5. Test long recordings, rapid start/stop, background interruption, phone-call interruption, and simultaneous iPhone/Watch transcription jobs.
6. Confirm the generated Info.plist contains `NSMicrophoneUsageDescription` and does not contain `NSSpeechRecognitionUsageDescription`.
7. Search production sources for `SFSpeechRecognizer`, `SFSpeechRecognitionRequest`, and `legacySFSpeech`; all must return zero results.

## Rollback

Keep the additive Core Data model even if transcription must be disabled. Roll back behavior with a feature flag or by disabling entry points; do not revert the shipped model version or delete the new columns. Saved recordings remain usable and can be retried by a later build.
