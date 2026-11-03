# OffRecord AI Journal Privacy Policy

**Last Updated: November 3, 2026**

## Our Promise

OffRecord AI Journal is built for private journaling. We do not run developer servers that receive your journal, we do not sell data, and we do not use analytics, advertising SDKs, tracking SDKs, or non-Apple third-party AI services.

This policy covers OffRecord on iPhone, iPad, Mac, and Apple Watch.

## What Data OffRecord AI Journal Processes

OffRecord AI Journal processes the following data to provide journaling features:

- **Voice Recordings**: Audio files recorded through the app
- **Transcriptions**: Text converted from voice recordings on device using Apple SpeechAnalyzer
- **Journal Entries**: Text you write or dictate, including entries you import from other apps
- **Mood Data**: Mood selections you make for your entries
- **Tags and Journals**: Tags you add to entries and the journals you create
- **Privacy Choices**: Keep Out of Friday and Skip Weekly Reflection on individual entries
- **AI Analysis**: Emotional patterns, personality insights, the search index, Weekly Reflection, Month in Review, Year in Review, and Session Prep summaries
- **Friday Data**: Friday's profile (personality model, emotional signature, and knowledge graph), her chat, your memory edits, generated entry titles, and Go Deeper questions
- **Weekly Reflection Data**: Weekly reports, report status, saved takeaways, evidence references, source visibility choices, and export preferences
- **Photos**: Images you attach to entries, including photos from a Journaling Suggestion you pick or from an import
- **Apple Watch Captures**: Mood, dictated text, audio manifests, audio files, transfer status, and receipts created by the watchOS companion
- **Settings**: Preferences such as theme, reminders, streaks, Weekly Reflection settings, app lock, iCloud sync, the Friday switch, Apple Health, and on-device transcription consent

## On-Device SpeechAnalyzer Transcription

If you choose to transcribe voice recordings, OffRecord uses Apple's SpeechAnalyzer framework:

- OffRecord shows an in-app disclosure before transcription begins.
- `SpeechTranscriber` is the preferred engine and `DictationTranscriber` provides additional locale coverage.
- Recognition runs entirely on your device. Audio is not sent to Apple or a speech-recognition server.
- Your device may download a language model from Apple before first use.
- If the selected language is unsupported, or you turn off transcription, your recording remains saved on the device and you can type the entry manually.
- You can turn off on-device transcription in Settings.

OffRecord does not send your audio, transcripts, journal entries, photos, Friday prompts, Weekly Reflection reports, the search index, or AI analysis to developer servers, speech-recognition servers, or non-Apple AI services.

## On-Device Language Model

When Apple Intelligence is available on your device, Friday uses Apple's on-device language model (`SystemLanguageModel` in the Foundation Models framework):

- It holds Friday's chat across turns, looks things up in your journal with three tools (search, mood counts, and people), writes short entry titles and Go Deeper questions, and can rephrase a Weekly Reflection's cover line and summary from the week's facts.
- The model runs on your device. OffRecord does not use Private Cloud Compute or any server model.
- Everything the model writes is checked against OffRecord's voice and safety rules. If a check fails, the app shows its own deterministic wording instead.
- High-risk text about self-harm or suicide is never sent to the model, analyzed, or quoted. Friday offers the Get Support sheet instead.
- Without Apple Intelligence, Friday answers from summaries built by the app.

## Where Your Data Lives

By default, your data is stored on your iPhone, iPad, or Mac using:

- **Core Data**: For entries, metadata, photos, tags, journals, Keep Out of Friday choices, and app state such as Weekly Reflection and review reports
- **Friday's local folder** (`Application Support/FridayLocal`): For Friday's profile, chat, memory edits, generated entry titles, and Go Deeper questions
- **UserDefaults**: For settings, preferences, and consent choices
- **Application Support Directory**: For audio recordings, the search index, and support files

### Friday's Local Folder

Friday's profile, chat, memory edits (Forget and Rename), generated entry titles, and Go Deeper questions are kept in one folder on the device:

- Files are written with complete file protection.
- The folder is excluded from device backups.
- The folder never syncs through iCloud, even when iCloud Sync is on. Each device rebuilds Friday's profile from your entries.
- Turning Friday off, or Erase All Data, deletes the whole folder.

### Mac App

The Mac app (Mac Catalyst) stores your journal the same way, in its own sandboxed container on the Mac, and uses the same iCloud container when iCloud Sync is on. Apple Health, widgets, Live Activities, Journaling Suggestions, and the Apple Watch app are not part of the Mac app.

### Apple Watch Quick Capture

If you use the Apple Watch companion, captures are stored on the watch first:

- Mood, Speak, and Record captures are saved to a durable watch outbox before sync.
- Recent on Apple Watch is an outbox/status view, not a journal archive.
- Watch complications and Smart Stack widgets show only generic Quick Capture status and do not show journal text, transcripts, or audio filenames.
- Captures transfer to the paired iPhone through Apple WatchConnectivity.
- Audio notes transfer as files; OffRecord does not treat audio metadata alone as an imported recording.
- The iPhone sends a receipt back to the watch after the capture is durably applied.

The watch companion does not send your journal to developer servers and does not add analytics, tracking, or advertising SDKs.

### Weekly Reflection

If Weekly Reflection is enabled, OffRecord prepares weekly reports from started entries in the selected week:

- Reports are generated on device from entry dates, text, mood, word count, source type, sentiment, topics, and short snippets.
- Reports are stored as app state in the journal store.
- Report-level source hiding affects only that report version and does not change the original journal entry. Skip Weekly Reflection on an entry leaves it out of every report.
- High-risk entries can count toward weekly eligibility and source management, but their text, snippets, topics, quotes, and evidence references are excluded from generated insights and exports.
- Weekly Reflection exports keep source quotes off by default.
- Weekly Reflection notifications use static copy and do not include journal text, names, snippets, themes, summaries, or quotes.

### Month in Review, Year in Review, and Session Prep

- Month in Review and Year in Review are generated on device from your entries and stored as app state in the journal store.
- The Year in Review share card replaces people's names with "someone" unless you turn names on.
- Session Prep builds a summary of a date range on device. It includes no quotes unless you pick them, and it replaces names unless you turn them on.
- These leave the app only when you share or export them.

### Keep Out of Friday and the Friday Switch

- **Keep Out of Friday** (per entry): the entry is never indexed for search by meaning, cited, learned from, quoted, or used in Friday's cards or saved chat. Weekly Reflection still counts it unless you also choose Skip Weekly Reflection.
- **Friday switch** (Settings): with Friday off, Friday reads nothing. Turning her off deletes her profile, chat, memory edits, cards, generated titles, and Go Deeper questions.

### Journaling Suggestions (iPhone)

On iPhone, OffRecord can open Apple's Journaling Suggestions picker:

- Apple prepares suggestions on your iPhone. OffRecord can't see them.
- When you pick a suggestion, OffRecord receives only that suggestion. It keeps the suggestion's title or reflection prompt as the entry's prompt and attaches its photos, up to five.
- Nothing from suggestions you don't pick reaches OffRecord.

### Importing From Other Apps

When you import entries (Day One, Apple Journal, Markdown or text files, or CSV):

- You choose the files in the system file picker. OffRecord can read only the files you choose.
- Files are read on your device. Nothing is uploaded.
- OffRecord shows a preview before anything is saved.

### Siri and Apple Intelligence

- Create Entry, Create Audio Entry, and Search adopt Apple's journal schemas. The entry they return to Siri carries metadata only (date, mood, starred state, word count, and whether it has a recording or photos), never journal text or photos.
- Ask Friday in Siri answers with a summary only: no quotes, no snippets, and no citations. A summary that repeats words from an entry is replaced by a count and date range.
- A high-risk question gets Friday's support line, and the app opens to the Get Support sheet.
- Intents that read or change the journal ask for device authentication.
- What you say to Siri is handled by Apple under Apple's privacy policy.

### Optional Apple Health

If you turn on Save Moods to Health in Settings, OffRecord saves the moods you choose to Apple Health as State of Mind samples:

- Only the mood and the time are saved. Journal text, transcripts, photos, and recordings are never written to Health.
- OffRecord asks for permission to write State of Mind data only. It never reads any Health data.
- Apple Health is off by default. You can turn it off in Settings or manage access in the Health app.
- Health data you choose to save is stored and protected by Apple Health, not by developer servers.
- Apple Health is not available in the Mac app.

### Optional iCloud Sync

If iCloud Sync is enabled, your journal syncs through your personal Apple iCloud account using Apple's CloudKit infrastructure:

- What syncs: entries, photos, tags, journals, Keep Out of Friday choices, and reports (Weekly Reflection, Month in Review, and Year in Review, including any wording the on-device model wrote for them).
- What doesn't sync: recordings, the search index, and Friday's local folder. Recordings stay on the device where they were recorded. Apple Watch recordings transfer to the paired iPhone through Apple WatchConnectivity so they can be attached to the daily entry.
- Sync uses your Apple ID and Apple's iCloud protections.
- OffRecord has no developer server access to your iCloud data.
- Settings shows the sync status. You can turn iCloud Sync off at any time; turning it off leaves your entries on the device and in iCloud.

## Erase All Data

Settings › Erase All Data deletes:

- every entry, recording, photo, tag, journal, and report
- Friday's local folder (profile, chat, memory edits, and generated text)
- the search index, OffRecord's Spotlight entries, the widget snapshot, and delivered notifications

Settings that hold no journal content, such as Lock, iCloud Sync, and theme, stay as they are. With iCloud Sync on, the deletions sync, so the data is removed from iCloud too. With iCloud Sync off, copies already in iCloud stay. The confirmation says which applies. Moods already saved to Apple Health stay in Health.

## What We Do NOT Do

- We do **NOT** collect personal data on developer servers.
- We do **NOT** use OpenAI, Anthropic, Gemini, or other non-Apple third-party AI services.
- We do **NOT** use Apple's Private Cloud Compute or any server-based language model.
- We do **NOT** use third-party analytics or tracking.
- We do **NOT** use third-party advertising.
- We do **NOT** share, sell, or transfer your data for advertising or marketing.
- We do **NOT** require an account or login.
- We do **NOT** use cookies or web tracking in the app.
- We do **NOT** access contacts or other personal data beyond photos and files you explicitly choose.

## AI Processing

OffRecord's journal intelligence stays on your device:

- **Mood Analysis**: On-device using Apple's NaturalLanguage framework
- **Friday Engine**: On-device logic that builds your personal model. The profile is rebuilt from your entries on each device.
- **On-Device Language Model**: Apple Foundation Models (`SystemLanguageModel`) when Apple Intelligence is available, as described above
- **Weekly Reflection**: On-device reports derived from your started entries. Reports can be dismissed, deleted, regenerated with report-level source choices, or exported.
- **Month in Review and Year in Review**: On-device reviews of a month or a year
- **Search by Meaning**: On-device search index and embeddings derived from your journal entries. This index is not synced to iCloud and can be rebuilt or deleted from Settings.
- **Safety Check**: On-device classifier that keeps high-risk text out of analysis and quotes

Voice transcription is separate from these journal analysis features and runs on device with Apple SpeechAnalyzer as described above.

## Permissions We Request

| Permission | Why We Need It | When It's Used |
|-----------|---------------|----------------|
| Microphone | To record voice entries | Only while actively recording |
| Face ID / Touch ID | To lock the app for privacy | Only when app lock is enabled |
| Notifications | To send daily journal reminders and Weekly Reflection reminders | Only if you enable reminders |
| Photo Library | To attach photos to entries | Only when you use the photo picker |
| Apple Health (write only) | To save the moods you choose as State of Mind | Only if you turn on Save Moods to Health |

All permissions are optional. The app functions without them in text-only mode. On-device transcription with SpeechAnalyzer does not need the separate Speech Recognition permission; it uses microphone access only. Journaling Suggestions and imports use system pickers, so OffRecord sees only what you pick.

## Photo Storage

Photos you attach to entries are:

- Stored in the app's sandboxed data store
- Compressed as JPEG files
- Synced through your personal iCloud account if iCloud Sync is enabled
- Not uploaded to developer servers
- Deleted when you delete the entry, use Erase All Data, or uninstall the app, subject to iCloud retention behavior if sync is enabled

## Data Retention

- Journal data stays on your device until you delete it.
- Erase All Data deletes the journal and everything derived from it, as described above.
- Uninstalling the app removes local app data.
- iCloud data can be managed through your iCloud settings.
- Audio files are stored in the app's sandboxed directory.
- Apple Watch captures remain in the watch outbox until imported by the paired iPhone or deleted by the watch's storage policy.
- Weekly Reflection reports stay in app data until you delete the report, erase your data, or uninstall the app.
- The search index can be deleted and rebuilt from Settings.
- Friday's local folder is deleted when you turn Friday off or erase your data.

## Children's Privacy

OffRecord AI Journal does not knowingly collect data from children under 13. Since we do not collect personal data on developer servers, there is no server-side child data collection.

## Third-Party Services

OffRecord AI Journal uses the following Apple services and frameworks:

- Apple SpeechAnalyzer with on-device SpeechTranscriber and DictationTranscriber for transcription
- Apple NaturalLanguage Framework for on-device text analysis
- Apple Foundation Models (on-device `SystemLanguageModel`) on devices with Apple Intelligence
- Apple CloudKit for optional iCloud Sync
- Apple HealthKit for optional, write-only State of Mind mood samples (iPhone and iPad)
- Apple Journaling Suggestions for the suggestion picker (iPhone)
- Apple App Intents for Siri, Shortcuts, and Apple Intelligence
- Apple WidgetKit for Home Screen widgets
- Apple WatchConnectivity for Apple Watch Quick Capture sync
- Apple WidgetKit complications and Smart Stack widgets for privacy-safe watch entry points

We do not integrate non-Apple third-party SDKs, analytics tools, advertising networks, or third-party AI APIs.

## App Store Privacy Labels

Based on Apple's App Privacy guidance:

**Data Not Collected**: OffRecord AI Journal does not collect data on developer servers, and journal analysis and speech recognition stay on device. Optional iCloud services are governed by Apple's privacy practices.

**Data Linked to You**: None by OffRecord.

**Data Used to Track You**: None.

## Your Rights and Controls

Since OffRecord does not collect your data on developer servers, control stays in the app and with your Apple account:

- You can export your data from Settings.
- You can delete individual entries, or delete everything with Erase All Data.
- You can keep any entry out of Friday, and out of Weekly Reflection.
- You can turn Friday off, which deletes what she learned.
- You can dismiss, delete, regenerate, or export Weekly Reflection reports from the app.
- You can disable iCloud Sync in Settings.
- You can turn off on-device transcription in Settings.
- You can uninstall the app to remove local data.
- iCloud data can be managed through Apple's iCloud settings.

## Changes to This Policy

We may update this privacy policy from time to time. We will notify you of changes by updating the "Last Updated" date at the top of this policy.

## Contact Us

If you have questions about this privacy policy:

- Email: saransh1337@gmail.com

## Summary

OffRecord AI Journal keeps private journaling on your device by default, transcribes recordings on device with Apple SpeechAnalyzer, runs Friday on device (with Apple's on-device language model where available, never a server model), keeps Friday's profile and chat in a local folder that never syncs, optionally saves moods (never journal text) to Apple Health, transfers Apple Watch captures through Apple WatchConnectivity, optionally syncs your journal through your personal iCloud, and does not send your journal to developer servers or non-Apple AI services.
