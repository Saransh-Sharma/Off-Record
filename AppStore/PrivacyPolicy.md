# OffRecord AI Journal Privacy Policy

**Last Updated: May 15, 2026**

## Our Promise

OffRecord AI Journal is built for private journaling. We do not run developer servers that receive your journal, we do not sell data, and we do not use analytics, advertising SDKs, tracking SDKs, or non-Apple third-party AI services.

## What Data OffRecord AI Journal Processes

OffRecord AI Journal processes the following data to provide journaling features:

- **Voice Recordings**: Audio files recorded through the app
- **Transcriptions**: Text converted from voice recordings using Apple Speech
- **Journal Entries**: Text you write or dictate
- **Mood Data**: Mood selections you make for your entries
- **AI Analysis**: Emotional patterns, personality insights, Semantic Memory, and your Friday model
- **Friday Data**: Personality model, emotional signature, and knowledge graph generated from your entries
- **Photos**: Images you attach to diary entries
- **Settings**: Preferences such as theme, reminders, app lock, iCloud sync, and Apple Speech consent

## Apple Speech Transcription

If you choose to transcribe voice recordings, OffRecord uses Apple's Speech framework:

- OffRecord asks for your permission before transcription begins.
- When your device is online, voice audio may be sent to Apple Speech for speech recognition.
- Apple Speech returns the transcript, and OffRecord saves that transcript in your journal.
- If you do not allow Apple Speech transcription, your recording is saved locally and you can type the entry manually.
- You can revoke Apple Speech transcription consent in Settings.

Apple Speech processing is provided by Apple and is subject to Apple's privacy protections and policies. OffRecord does not send your audio, transcripts, journal entries, photos, Friday prompts, Semantic Memory, or AI analysis to developer servers or non-Apple AI services.

## Where Your Data Lives

By default, your data is stored locally on your iPhone or iPad using:

- **Core Data**: For diary entries, metadata, photos, and AI state
- **UserDefaults**: For settings, preferences, and consent choices
- **Application Support Directory**: For local audio recordings and support files

### Optional iCloud Sync

If iCloud Sync is enabled, entries and attached photos sync through your personal Apple iCloud account using Apple's CloudKit infrastructure:

- Sync uses your Apple ID and Apple's iCloud protections.
- OffRecord has no developer server access to your iCloud data.
- Audio recordings stay on the device where they were recorded.
- You can disable iCloud Sync in Settings.

## What We Do NOT Do

- We do **NOT** collect personal data on developer servers.
- We do **NOT** use OpenAI, Anthropic, Gemini, or other non-Apple third-party AI services.
- We do **NOT** use third-party analytics or tracking.
- We do **NOT** use third-party advertising.
- We do **NOT** share, sell, or transfer your data for advertising or marketing.
- We do **NOT** require an account or login.
- We do **NOT** use cookies or web tracking.
- We do **NOT** access contacts or other personal data beyond photos you explicitly attach to entries.

## AI Processing

OffRecord's journal intelligence is designed to stay local:

- **Mood Analysis**: On-device using Apple's NaturalLanguage framework
- **Friday Engine**: On-device logic that builds your personal model
- **Semantic Memory**: On-device search index and embeddings derived from your journal entries. This index is not synced to iCloud and can be rebuilt or deleted from Settings.
- **Foundation Models Friday Responder**: Optional on-device Apple Foundation Models phrasing layer on supported systems

Voice transcription is separate from these journal analysis features and may use Apple Speech as described above.

## Permissions We Request

| Permission | Why We Need It | When It's Used |
|-----------|---------------|----------------|
| Microphone | To record voice diary entries | Only while actively recording |
| Speech Recognition | To transcribe voice to text with Apple Speech | Only when processing a recording or voice search after consent |
| Face ID / Touch ID | To lock the app for privacy | Only when app lock is enabled |
| Notifications | To send daily journal reminders | Only if you enable reminders |
| Photo Library | To attach photos to diary entries | Only when you use the photo picker |

All permissions are optional. The app functions without them in text-only mode.

## Photo Storage

Photos you attach to diary entries are:

- Stored in the app's sandboxed data store
- Compressed as JPEG files
- Synced through your personal iCloud account if iCloud Sync is enabled
- Not uploaded to developer servers
- Deleted when you delete the entry or uninstall the app, subject to iCloud retention behavior if sync is enabled

## Data Retention

- Local journal data stays on your device until you delete it.
- Uninstalling the app removes local app data.
- iCloud data can be managed through your iCloud settings.
- Audio files are stored locally in the app's sandboxed directory.
- Derived Semantic Memory data can be deleted and rebuilt from Settings.

## Children's Privacy

OffRecord AI Journal does not knowingly collect data from children under 13. Since we do not collect personal data on developer servers, there is no server-side child data collection.

## Third-Party Services

OffRecord AI Journal uses the following Apple services and frameworks:

- Apple Speech Framework for transcription
- Apple NaturalLanguage Framework for local NLP
- Apple Foundation Models on supported systems for local Friday phrasing
- Apple CloudKit for optional iCloud Sync
- Apple WidgetKit for Home Screen widgets

We do not integrate non-Apple third-party SDKs, analytics tools, advertising networks, or third-party AI APIs.

## App Store Privacy Labels

Based on Apple's App Privacy guidance:

**Data Not Collected**: OffRecord AI Journal does not collect data on developer servers, and journal analysis stays on device. Apple services such as Apple Speech and iCloud are governed by Apple's privacy practices.

**Data Linked to You**: None by OffRecord.

**Data Used to Track You**: None.

## Your Rights and Controls

Since OffRecord does not collect your data on developer servers, control stays in the app and with your Apple account:

- You can export your data from Settings.
- You can delete individual entries or all local app data.
- You can disable iCloud Sync in Settings.
- You can revoke Apple Speech transcription consent in Settings.
- You can uninstall the app to remove local data.
- iCloud data can be managed through Apple's iCloud settings.

## Changes to This Policy

We may update this privacy policy from time to time. We will notify you of changes by updating the "Last Updated" date at the top of this policy.

## Contact Us

If you have questions about this privacy policy:

- Email: intrepidkarthi@gmail.com

## Summary

OffRecord AI Journal keeps private journaling local by default, uses Apple Speech only with permission for transcription, optionally syncs entries and photos through your personal iCloud, and does not send your journal to developer servers or non-Apple AI services.
