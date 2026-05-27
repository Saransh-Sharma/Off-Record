# Weekly Reflection

## Summary

Weekly Reflection is OffRecord's local end-of-week ritual. It builds a calm report from started journal entries in the current Monday-Sunday period, shows the current state on Home, keeps report history in Insights, and lets users review sources, save a takeaway, regenerate with report-level source changes, and export the result.

The product invariant is local first. Weekly Reflection uses deterministic generation over existing journal data and persists Codable report payloads in existing AI state. It does not add a Core Data migration, cloud AI, developer-server processing, global entry privacy flags, or app-wide source exclusion controls.

## User-Facing Behavior

- The Home card appears below the Today hero when Weekly Reflection is enabled, the Home card setting is on, and the current report is Home-visible.
- The report detail screen shows a cover sentence, summary, optional emotional arc, themes, small wins, frictions, questions, source controls, saved takeaway, export, dismiss, and delete.
- Insights history shows report versions that are visible in history.
- Dismiss hides a report from Home but preserves it in history.
- Delete removes the report from history visibility.
- Regeneration creates a new version, supersedes the previous version, and applies hidden source IDs only to the new report version.
- Weekly local notifications use static copy and open `offrecord://weekly-reflection/current`.

## Eligibility And Periods

Weekly periods are Monday 00:00 through Sunday 23:59:59 in the user's local calendar.

Eligibility is evaluated after applying report-hidden entry IDs:

| Eligibility | Rule |
|---|---|
| `empty` | `entryCount == 0` or `wordCount < 150` |
| `light` | 1-2 entries and 150-599 words |
| `full` | 3+ entries with at least 150 words, or 600+ words |

Started entries only are eligible. Deleted or unavailable entries are not used for generation. Unavailable IDs from an older report version remain visible as unavailable source metadata when relevant.

## Generation Pipeline

Weekly Reflection takes compact snapshots from `DiaryEntry`:

- entry ID
- date and updated date
- mood
- text
- word count
- source type: text, voice transcript, or photo note
- sentiment from `ProactiveReflectionAnalyzer`

The generator splits entries into two sets:

- `periodEntries`: all eligible non-hidden started entries in the week. These drive counts, included IDs, source management, input signature, and safety level.
- `insightEntries`: `periodEntries` minus high-risk entries. These drive topics, emotional arc, themes, evidence refs, snippets, wins, frictions, questions, and export quotes.

Output limits:

- hero sentence: 25 words or fewer
- summary: 120 words or fewer
- full report: 2-5 themes
- light report: at most 2 themes
- wins: 1-3
- frictions: 1-3
- questions: 1-3
- evidence refs must point only to included, available, non-high-risk entries

## Safety Rules

Weekly Reflection avoids clinical or certainty-based language. Copy should stay observational and grounded in the user's entries, using phrasing such as "your entries suggest", "you wrote about", and "this came up".

High-risk entries still count toward weekly eligibility and source management, but are excluded from generated insight fields:

- no high-risk text in hero or summary
- no high-risk topics in themes
- no high-risk snippets or evidence quotes
- no high-risk text in wins, frictions, questions, or export

If every eligible entry is high-risk, the report is still created as a support-oriented reflection with no themes or evidence refs. It keeps included IDs for source management but never quotes those entries.

## Persistence And Status

Reports are stored as Codable payloads in existing `AIState` under the weekly reflection repository state type. Core Data journal entries remain the source of truth; reports are derived local state.

Primary report types:

- `WeeklyReflectionReport`
- `WeeklyReflectionTheme`
- `WeeklyReflectionEvidenceRef`
- `WeeklyReflectionTakeaway`
- `WeeklyReflectionSettings`

Statuses:

| Status | Home | History |
|---|---:|---:|
| `ready` | visible | visible |
| `seen` | visible | visible |
| `insufficientData` | visible | visible |
| `failed` | visible | visible |
| `dismissed` | hidden | visible |
| `superseded` | hidden | hidden |
| `deleted` | hidden | hidden |

`inputSignature` is based on the current period snapshots after hidden IDs are applied. Opening the current deep link should not create a new version when the signature is unchanged. If the report is stale, opening current may generate one new version and supersede the prior one.

## Sources, Export, And Settings

The source sheet lists available entries in the report period, not only currently included entries. Available rows support:

- opening the source entry
- toggling inclusion in the next regenerated version
- updating the report with hidden IDs equal to available period entries whose include toggle is off

Unavailable IDs are shown as unavailable only. They cannot be opened or re-included.

Export supports Markdown and plain text. Source quotes are excluded by default and included only when the user explicitly enables quote export. High-risk quotes are never exported, even when quote export is enabled.

Settings controls:

- enable Weekly Reflection
- reminder weekday, default Sunday
- reminder time, default 7:00 PM
- show Home card
- send notification
- local-only processing disclosure

When notification sending is enabled, OffRecord requests alert and sound permission if notification authorization is not determined. If permission is denied, `sendNotification` remains off and Settings explains how to enable notifications.

## Routes And Notifications

Supported deep links:

- `offrecord://weekly-reflection/current`
- `offrecord://weekly-reflection/{reportID}`

Notification requirements:

- identifier is separate from daily reminders
- trigger is a recurring weekly `UNCalendarNotificationTrigger`
- title is exactly `Your weekly reflection is ready`
- body is exactly `A private look back at your week.`
- notification payload must not include journal text, snippets, names, themes, summaries, quotes, or source metadata

Cold-launch notification taps store the route until private content can be navigated. Active-app taps route immediately when onboarding and app lock state allow private navigation.

## Testing And QA

Automated coverage should include:

- Monday-Sunday period boundaries across local timezone changes
- empty, light, and full eligibility thresholds
- repository save, load, version, supersede, dismiss, delete, and history visibility
- hidden source regeneration and re-inclusion
- high-risk exclusion from insight fields, evidence refs, and export
- validation of output limits and evidence refs
- notification content and recurring trigger privacy
- source sheet open-entry and include-toggle paths
- Home ready, light, empty, failed, dismissed, and high-risk support states
- current deep link opening without version churn when the signature is unchanged

Useful launch arguments for UI tests:

```text
-UITesting
-WeeklyReflectionUITest
-WeeklyReflectionEmpty
-WeeklyReflectionFailed
-WeeklyReflectionDismissed
-WeeklyReflectionHighRisk
```

Verification commands used for this feature should target installed simulators. If `iPhone 16 Pro Max, OS=18.6` is unavailable or the embedded watch target blocks the scheme, use an installed iOS simulator and install the matching watchOS 26.2 platform/runtime before full embedded app tests.

## Contributor Checklist

Before changing Weekly Reflection:

- Keep generation deterministic and local-only.
- Do not add developer-server processing or non-Apple AI APIs.
- Keep report persistence in AI state unless a migration is explicitly planned.
- Keep source hiding report-version scoped.
- Do not add global entry private/exclude controls as part of this feature.
- Keep notification copy static and journal-free.
- Keep high-risk text out of generated insight fields and exports.
- Add or update tests when changing eligibility, safety, generation, source management, notifications, deep links, or export.

Related implementation files:

- `OffRecord/WeeklyReflectionModels.swift`
- `OffRecord/WeeklyReflectionServices.swift`
- `OffRecord/WeeklyReflectionController.swift`
- `OffRecord/WeeklyReflectionViews.swift`
- `OffRecord/StatsView.swift`
- `OffRecord/SettingsView.swift`
- `OffRecord/OffRecordNavigationRouter.swift`
- `OffRecordTests/WeeklyReflectionTests.swift`
- `OffRecordUITests/WeeklyReflectionUITests.swift`
