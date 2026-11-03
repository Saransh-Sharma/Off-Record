# OffRecord AI Journal - App Store Submission Checklist

## Pre-Submission

### Code & Build
- [ ] All source files compile without errors
- [ ] No warnings in Release build
- [ ] Minimum deployment target set (iOS/iPadOS 26.0+)
- [ ] Mac Catalyst deployment target resolves to macOS 26.0+
- [ ] watchOS deployment target set (watchOS 26.0+)
- [ ] watchOS 26.2 platform/runtime installed before embedded watch build verification
- [ ] Bundle identifier: `com.singularity.offrecord`
- [ ] Watch bundle identifier: `com.singularity.offrecord.watchkitapp`
- [ ] Watch widget bundle identifier: `com.singularity.offrecord.watchkitapp.OffRecordWatchWidget`
- [ ] Watch companion app bundle identifier setting: `com.singularity.offrecord`
- [ ] Version: 1.5.0 (every target)
- [ ] Build number: 15 (every target)
- [ ] App Group configured: `group.com.singularity.offrecord`
- [ ] `OffRecord` embeds `OffRecordWatch`, and `OffRecordWatch` embeds `OffRecordWatchWidget`
- [ ] Archive builds successfully in Release configuration, for iOS and for Mac Catalyst
- [ ] Mac Catalyst uses the same bundle ID (`DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER = NO`); the watch app and widget extension are filtered out of the Mac build

### App Icon
- [ ] 1024x1024 App Store icon (already in Assets.xcassets)
- [ ] watchOS app icon content included in `AppIcon`
- [ ] No transparency or alpha channel
- [ ] No rounded corners (iOS applies them automatically)

### Screenshots (Required)
- [ ] iPhone 6.9" display (1320 x 2868) - at least 3 screenshots (`AppStore/screenshots/iPhone_69/`)
- [ ] iPad 13" display (2064 x 2752) - required because the app supports iPad (`AppStore/screenshots/iPad_13/`)
- [ ] Mac (16:10, for example 2880 x 1800) - required once the macOS platform is added
- See `ScreenshotAssets.md` for caption text and layout guide

### Metadata (Ready in AppStoreMetadata.md)
- [x] App Name: "OffRecord AI Journal"
- [x] Subtitle: "Your Private AI Assistant"
- [x] Description (under 4000 chars)
- [x] Keywords (under 100 chars)
- [x] Promotional Text
- [x] What's New text
- [x] Category: Lifestyle / Productivity
- [x] Age Rating: 4+
- [x] Copyright
- [x] Support URL
- [x] Privacy Policy URL

### Privacy (Ready in PrivacyPolicy.md)
- [x] Privacy Policy written
- [x] Privacy Policy hosted at URL
- [x] App Privacy labels configured (Data Not Collected)
- [x] Apple Speech transcription disclosure and consent shown before transcription
- [x] Apple Watch Quick Capture privacy documented: local watch outbox, WatchConnectivity transfer, privacy-safe complication/Smart Stack content, and no analytics

### App Review
- [x] Review notes prepared (in metadata.json)
- [ ] Demo video prepared (optional but recommended)
- [ ] No placeholder content in screenshots
- [ ] All links in app work (support URL, privacy URL)

## Ship Steps for 1.5.0

### CloudKit Schema (model version 3)
- [ ] With a development build and iCloud Sync on, create a tag, a second journal, and a Keep Out of Friday entry. The app doesn't call `initializeCloudKitSchema`, so this is what puts the new types in the development schema:
  - record types `CD_Tag` and `CD_Journal`
  - fields `CD_aiExclusion` and `CD_journal` on `CD_DiaryEntry`
  - `CDMR`, the record type that holds the many-to-many relationship between tags and entries
- [ ] Check them in CloudKit Console for `iCloud.com.singularity.offrecord`, then **Deploy Schema Changes to Production before release**. Without this, release builds can't sync tags, journals, or Keep Out of Friday.

### Capabilities
- [ ] Enable Journaling Suggestions on the App ID (`com.apple.developer.journal.allow` with `suggestions`), then regenerate the iOS provisioning profiles.

### Mac (Mac Catalyst)
- [ ] App Store Connect: add the macOS platform to the existing app record. Same bundle ID, `com.singularity.offrecord`.
- [ ] Mac entitlements review (`OffRecord/OffRecord-macCatalyst.entitlements`):
  - App Sandbox and Hardened Runtime on
  - `com.apple.security.device.audio-input` for recording
  - `com.apple.security.files.user-selected.read-only` for imports
  - iCloud container `iCloud.com.singularity.offrecord` with CloudKit, and `com.apple.developer.aps-environment` set to production in the distribution build
  - app group `group.com.singularity.offrecord` registered for the Mac
  - no HealthKit or Journaling Suggestions entitlements (neither runs on Mac)
- [ ] Archive and upload the Mac Catalyst build as 1.5.0 (15).

### Privacy Label
- [ ] Confirm the App Privacy label stays "Data Not Collected". 1.5.0 adds no collection: the on-device model, Journaling Suggestions, imports, and Siri keep data on the device or in the user's own iCloud.
- [ ] The hosted privacy policy shows "Last Updated: November 3, 2026".

### Device QA
- [ ] Siri: Ask Friday answers after Face ID, and Open in Friday works; a heavy question opens Get Support over the Lock Screen.
- [ ] Journaling Suggestions: the picker on iPhone starts an entry and attaches photos, up to 5.
- [ ] iCloud: turning Sync on and off with a real account applies without a relaunch; a second device sees entries, tags, and journals after the schema deploy.
- [ ] Mac app visual QA: sidebar, menu commands (⌘N, ⇧⌘R, ⌘F, ⌘,), and Settings.
- [ ] Apple Watch: captures land in the main journal.
- [ ] On-device model quality on an Apple Intelligence device: chat tools, titles, Go Deeper, and Weekly Reflection wording.

## App Store Connect Setup

### Create App Record
1. Go to App Store Connect > My Apps > "+"
2. Platforms: iOS and macOS (the Mac app is Mac Catalyst with the same bundle ID)
3. Name: OffRecord AI Journal
4. Primary Language: English (US)
5. Bundle ID: com.singularity.offrecord
6. SKU: OFFRECORD-Journal

### App Information
1. Category: Lifestyle
2. Secondary Category: Lifestyle
3. Content Rights: Does not contain third-party content
4. Age Rating: Configure with `rating_config.json`

### Pricing and Availability
1. Price: Free
2. Availability: All territories

### App Privacy
1. Data Collection: "No, we do not collect data from this app"
2. No data types to declare for developer collection
3. Review notes explain on-device SpeechAnalyzer transcription, optional iCloud Sync, optional write-only Apple Health moods, the `audio` background mode (recording Live Activity controls), Apple Watch Quick Capture via WatchConnectivity, the on-device language model, Journaling Suggestions, imports, and the Mac app

### Version Information
1. Upload screenshots for each device size, including Mac
2. Add promotional text
3. Add description
4. Add keywords
5. Add What's New
6. Add support URL
7. Add marketing URL (optional)

## Upload Process

### Using Xcode
1. Archive: Product > Archive
2. Distribute App > App Store Connect
3. Upload
4. Wait for processing (5-30 minutes)

### Using Fastlane (Recommended)
```bash
# Install fastlane
gem install fastlane

# Initialize (first time)
cd OffRecord
fastlane init

# Upload metadata
fastlane deliver

# Build and upload
fastlane gym
fastlane deliver --ipa path/to/offrecord.ipa
```

### Using xcrun
```bash
# Archive
xcodebuild archive \
  -project OffRecord.xcodeproj \
  -scheme OffRecord \
  -archivePath build/offrecord.xcarchive

# Export IPA
xcodebuild -exportArchive \
  -archivePath build/offrecord.xcarchive \
  -exportPath build/ \
  -exportOptionsPlist ExportOptions.plist

# Upload
xcrun altool --upload-app \
  -f build/offrecord.ipa \
  -t ios \
  -u YOUR_APPLE_ID \
  -p YOUR_APP_SPECIFIC_PASSWORD
```

## Post-Submission

- [ ] Monitor App Store Connect for review status
- [ ] Respond to any App Review feedback within 24 hours
- [ ] Prepare marketing materials for launch day
- [ ] Set up App Store page URL for sharing
- [ ] Monitor crash reports via Xcode Organizer
- [ ] Plan the next release from the Next section of `ROADMAP.md`
