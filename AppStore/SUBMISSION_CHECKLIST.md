# OffRecord AI Journal - App Store Submission Checklist

## Pre-Submission

### Code & Build
- [ ] All source files compile without errors
- [ ] No warnings in Release build
- [ ] Minimum deployment target set (iOS/iPadOS 26.0+)
- [ ] watchOS deployment target set (watchOS 26.0+)
- [ ] watchOS 26.2 platform/runtime installed before embedded watch build verification
- [ ] Bundle identifier: `com.singularity.offrecord`
- [ ] Watch bundle identifier: `com.singularity.offrecord.watchkitapp`
- [ ] Watch widget bundle identifier: `com.singularity.offrecord.watchkitapp.OffRecordWatchWidget`
- [ ] Watch companion app bundle identifier setting: `com.singularity.offrecord`
- [ ] Version: 1.4.0
- [ ] Build number: 14
- [ ] App Group configured: `group.com.singularity.offrecord`
- [ ] `OffRecord` embeds `OffRecordWatch`, and `OffRecordWatch` embeds `OffRecordWatchWidget`
- [ ] Archive builds successfully in Release configuration

### App Icon
- [ ] 1024x1024 App Store icon (already in Assets.xcassets)
- [ ] watchOS app icon content included in `AppIcon`
- [ ] No transparency or alpha channel
- [ ] No rounded corners (iOS applies them automatically)

### Screenshots (Required)
- [ ] iPhone 6.9" display (1320 x 2868) - at least 3 screenshots (`AppStore/screenshots/iPhone_69/`)
- [ ] iPad 13" display (2064 x 2752) - required because the app supports iPad (`AppStore/screenshots/iPad_13/`)
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

## App Store Connect Setup

### Create App Record
1. Go to App Store Connect > My Apps > "+"
2. Platform: iOS
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
3. Review notes explain on-device SpeechAnalyzer transcription, optional iCloud Sync, optional write-only Apple Health moods, the `audio` background mode (recording Live Activity controls), and Apple Watch Quick Capture via WatchConnectivity

### Version Information
1. Upload screenshots for each device size
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
- [ ] Plan v1.1 features based on user feedback
