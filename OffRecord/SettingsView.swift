import SwiftUI
import CoreData
import AppIntents
#if os(iOS)
import UIKit
#endif

struct SettingsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ObservedObject private var reminderManager = ReminderManager.shared
    @ObservedObject private var lockManager = AppLockManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var goalManager = GoalManager.shared
    @ObservedObject private var semanticMemory = SemanticMemoryIndexController.shared

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \DiaryEntry.date, ascending: true)],
        predicate: DiaryEntry.startedEntryPredicate,
        animation: .default)
    private var entries: FetchedResults<DiaryEntry>

    @State private var showPermissionDeniedAlert = false
    @State private var showCloudSyncRestartAlert = false
    @State private var showDeleteSemanticIndexConfirm = false

    // Export states
    @State private var showExportSheet = false
    @State private var selectedYear: Int?
    @State private var selectedMonth: Int?
    @State private var selectedExportPeriod: ExportPeriod = .yearly
    @State private var selectedPaperSize: PDFPaperSize = .a4
    @State private var starredOnly: Bool = false
    @State private var isExporting = false
    @State private var exportURL: URL?
    @State private var exportError: String?

    // Author info for PDF export
    @AppStorage("authorName") private var authorName: String = ""
    @AppStorage("authorDescription") private var authorDescription: String = ""
    @AppStorage("iCloudSyncEnabled") private var iCloudSyncEnabled: Bool = true
    @AppStorage(SpeechTranscriptionConsent.appleSpeechProcessingKey) private var appleSpeechProcessingConsentGranted: Bool = false
    @AppStorage(JournalSpotlightIndexer.isEnabledDefaultsKey) private var spotlightMetadataIndexingEnabled: Bool = true
    @State private var showSearchSiriTip = true

    private var startedEntries: [DiaryEntry] { entries.startedEntries }

    enum ExportPeriod: String, CaseIterable, Identifiable {
        case monthly = "Monthly"
        case quarterly = "Quarterly"
        case yearly = "Yearly"

        var id: String { rawValue }
    }

    // Storage states
    @State private var audioStorageBytes: Int64 = 0
    @State private var photoStorageBytes: Int64 = 0
    @State private var databaseStorageBytes: Int64 = 0
    @State private var isCalculatingStorage = false
    @State private var showDeleteAudioConfirm = false
    @State private var settingsStats: JournalStatsSnapshot = .empty

    private var entriesSignature: String {
        entries.map { entry in
            let updated = entry.updatedAt?.timeIntervalSinceReferenceDate ?? 0
            return "\(entry.objectID.uriRepresentation().absoluteString):\(updated)"
        }
        .joined(separator: "|")
    }

    var body: some View {
        Form {
            exportSection
            appearanceSection
            journalingGoalSection
            securitySection
            localAIPrivacySection
            semanticMemorySection
            systemSearchSection
            dailyReminderSection
            storageSection
            iCloudSection
            privacySection
            backupSection
            aboutSection
        }
        .scrollContentBackground(.hidden)
        .background(OffRecordColor.appBackgroundGradient)
        .onAppear {
            calculateStorage()
        }
        .task(id: "\(entriesSignature)-\(goalManager.weeklyTarget)-\(goalManager.isEnabled)") {
            await refreshSettingsStats()
        }
        .navigationTitle("Settings")
        .alert("Notifications Disabled", isPresented: $showPermissionDeniedAlert) {
            #if os(iOS)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            #endif
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please enable notifications for OffRecord AI Journal in Settings to receive daily reminders.")
        }
        .alert("Export error", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(exportError ?? "")
        }
        .alert("Restart Required", isPresented: $showCloudSyncRestartAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Restart OffRecord AI Journal for the iCloud sync change to take effect.")
        }
        .alert("Delete Semantic Memory Index?", isPresented: $showDeleteSemanticIndexConfirm) {
            Button("Delete Local Index", role: .destructive) {
                semanticMemory.deleteIndex()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes only derived local search data. Your journal entries, photos, audio, exports, widgets, and iCloud sync are not affected.")
        }
        .sheet(item: Binding(
            get: { exportURL.map { IdentifiableURL(url: $0) } },
            set: { if $0 == nil { exportURL = nil } }
        )) { item in
            #if os(iOS)
            ShareSheet(activityItems: [item.url])
            #else
            Text("PDF export is available on iOS.")
            #endif
        }
        .onChange(of: spotlightMetadataIndexingEnabled) { _, enabled in
            if enabled {
                JournalSpotlightIndexer.shared.rebuild(entries: startedEntries)
            } else {
                JournalSpotlightIndexer.shared.deleteAll()
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var exportSection: some View {
        Section(header: Text("Export"), footer: Text("Your name and description will appear on the cover page of exported PDFs.")) {
            TextField("Your name", text: $authorName)
            TextField("Description (optional)", text: $authorDescription)

            if years.isEmpty {
                Text("No entries to export yet.")
                    .foregroundColor(OffRecordColor.textSecondary)
            } else {
                Picker("Period", selection: $selectedExportPeriod) {
                    ForEach(ExportPeriod.allCases) { period in
                        Text(period.rawValue).tag(period)
                    }
                }

                let yearBinding = Binding<Int>(
                    get: { selectedYear ?? years.last ?? Calendar.current.component(.year, from: Date()) },
                    set: { selectedYear = $0 }
                )

                Picker("Year", selection: yearBinding) {
                    ForEach(years, id: \.self) { year in
                        Text(String(year)).tag(year)
                    }
                }

                if selectedExportPeriod == .monthly {
                    let monthBinding = Binding<Int>(
                        get: { selectedMonth ?? currentMonth },
                        set: { selectedMonth = $0 }
                    )

                    Picker("Month", selection: monthBinding) {
                        ForEach(1...12, id: \.self) { month in
                            Text(monthName(month)).tag(month)
                        }
                    }
                } else if selectedExportPeriod == .quarterly {
                    let quarterBinding = Binding<Int>(
                        get: { selectedMonth ?? currentQuarter },
                        set: { selectedMonth = $0 }
                    )

                    Picker("Quarter", selection: quarterBinding) {
                        Text("Q1 (Jan - Mar)").tag(1)
                        Text("Q2 (Apr - Jun)").tag(2)
                        Text("Q3 (Jul - Sep)").tag(3)
                        Text("Q4 (Oct - Dec)").tag(4)
                    }
                }

                Picker("Paper size", selection: $selectedPaperSize) {
                    ForEach(PDFPaperSize.allCases) { size in
                        Text(size.rawValue).tag(size)
                    }
                }

                Toggle("Only starred entries", isOn: $starredOnly)

                Button {
                    generatePDF()
                } label: {
                    HStack {
                        Text("Export as PDF")
                        Spacer()
                        if isExporting {
                            ProgressView()
                        } else {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
                .disabled(isExporting)
            }
        }
    }

    @ViewBuilder
    private var appearanceSection: some View {
        Section {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: horizontalSizeClass == .regular ? 6 : 4), spacing: 12) {
                ForEach(AppTheme.allCases) { theme in
                    ThemeButton(
                        theme: theme,
                        isSelected: themeManager.selectedTheme == theme
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            themeManager.selectedTheme = theme
                            HapticManager.shared.themeChanged()
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        } header: {
            Text("Appearance")
        } footer: {
            Text("Choose a soft color theme that suits your style.")
        }
    }

    @ViewBuilder
    private var journalingGoalSection: some View {
        Section {
            Toggle("Enable weekly goal", isOn: $goalManager.isEnabled)

            if goalManager.isEnabled {
                Stepper("Target: \(goalManager.weeklyTarget) entries/week", value: $goalManager.weeklyTarget, in: 1...7)

                Toggle("Notify when goal reached", isOn: $goalManager.notifyOnGoal)
            }
        } header: {
            Text("Journaling Goal")
        } footer: {
            Text("Set a weekly journaling target to build a consistent habit.")
        }
    }

    @ViewBuilder
    private var securitySection: some View {
        Section(header: Text("Privacy Lock")) {
            Toggle("Require \(lockManager.biometryTypeName) to open OffRecord", isOn: $lockManager.isEnabled)

            if lockManager.isEnabled {
                Text("Your journal locks when you leave the app. OffRecord never sees or stores your \(lockManager.biometryTypeName).")
                    .font(OffRecordTypography.metadata)
                    .foregroundColor(OffRecordColor.textSecondary)
            }

            if !lockManager.biometricsAvailable {
                Text("If \(lockManager.biometryTypeName) is unavailable, iOS will use your device passcode.")
                    .font(OffRecordTypography.metadata)
                    .foregroundColor(OffRecordColor.textSecondary)
            }
        }
    }

    @ViewBuilder
    private var localAIPrivacySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                PrivacyInfoRow(
                    icon: "cpu.fill",
                    title: "Local AI on your device",
                    description: "Mood analysis, Friday insights, Semantic Memory, and knowledge graph updates run on this device."
                )
                PrivacyInfoRow(
                    icon: "wifi.slash",
                    title: "Core app works offline",
                    description: "Core journaling and local AI insights work without an internet connection. Voice transcription may use Apple Speech when you allow it."
                )
                PrivacyInfoRow(
                    icon: "person.fill.xmark",
                    title: "No accounts or tracking",
                    description: "No accounts, analytics, tracking, developer AI servers, or non-Apple AI services."
                )

                Toggle("Apple Speech transcription", isOn: $appleSpeechProcessingConsentGranted)
                    .accessibilityIdentifier("settings.privacy.appleSpeechConsentToggle")

                Text(SpeechTranscriptionConsent.settingsDescription)
                    .font(OffRecordTypography.metadata)
                    .foregroundColor(OffRecordColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
        } header: {
            Text("Local AI & Offline Privacy")
        } footer: {
            Text("Optional iCloud Sync is separate and uses your personal Apple iCloud account, not an OffRecord server.")
        }
    }

    @ViewBuilder
    private var semanticMemorySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(OffRecordColor.surfaceLavender)
                            .frame(width: 38, height: 38)
                        Image(systemName: "brain.head.profile")
                            .font(OffRecordTypography.bodySmall)
                            .foregroundColor(OffRecordColor.textLavender)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Semantic Memory")
                            .font(OffRecordTypography.labelMedium)
                        Text(semanticMemory.statusMessage)
                            .font(OffRecordTypography.metadata)
                            .foregroundColor(OffRecordColor.textSecondary)
                            .lineLimit(2)
                            .accessibilityIdentifier("semanticMemory.statusMessage")
                    }

                    Spacer()

                    if semanticMemory.isBuilding {
                        ProgressView()
                    }
                }

                if semanticMemory.isBuilding {
                    ProgressView(value: semanticMemory.progress)
                        .accessibilityIdentifier("semanticMemory.progress")
                }

                HStack {
                    Text("Indexed chunks")
                    Spacer()
                    Text("\(semanticMemory.chunkCount)")
                        .foregroundColor(OffRecordColor.textSecondary)
                        .accessibilityIdentifier("semanticMemory.chunkCount")
                }

                if semanticMemory.usesFallbackEmbeddings {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("Apple embedding assets were unavailable, so OffRecord is using a local lexical fallback until rebuild succeeds.")
                    }
                    .font(OffRecordTypography.metadata)
                    .foregroundColor(OffRecordColor.textPeach)
                    .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("semanticMemory.fallbackWarning")
                }

                Button {
                    semanticMemory.rebuildIndex(entries: startedEntries)
                    JournalSpotlightIndexer.shared.rebuild(entries: startedEntries)
                } label: {
                    Label("Rebuild Semantic Memory", systemImage: "arrow.clockwise")
                }
                .accessibilityIdentifier("semanticMemory.rebuild")
                .disabled(semanticMemory.isBuilding)

                Button(role: .destructive) {
                    showDeleteSemanticIndexConfirm = true
                } label: {
                    Label("Delete Local Semantic Index", systemImage: "trash")
                }
                .accessibilityIdentifier("semanticMemory.delete")
                .disabled(semanticMemory.isBuilding && semanticMemory.chunkCount == 0)
            }
            .padding(.vertical, 4)
        } header: {
            Text("Semantic Memory")
                .accessibilityIdentifier("semanticMemory.section")
        } footer: {
            Text("Embeddings are derived locally from your journal entries and are not synced to iCloud. If Apple model assets are requested, only model files are downloaded; journal text stays on device.")
        }
    }

    @ViewBuilder
    private var systemSearchSection: some View {
        Section {
            Toggle("Show entries in Spotlight", isOn: $spotlightMetadataIndexingEnabled)
                .accessibilityIdentifier("settings.systemSearch.spotlightToggle")

            Text("Spotlight uses private metadata only: date, mood, starred state, word count, and whether an entry has voice or photos. Raw journal text, transcripts, photo thumbnails, and audio filenames stay out of system search.")
                .font(OffRecordTypography.metadata)
                .foregroundColor(OffRecordColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            ShortcutsLink()
                .accessibilityIdentifier("settings.systemSearch.shortcutsLink")

            SiriTipView(intent: SearchJournalIntent(), isVisible: $showSearchSiriTip)
                .siriTipViewStyle(.automatic)

            Button {
                JournalSpotlightIndexer.shared.rebuild(entries: startedEntries)
            } label: {
                Label("Rebuild Spotlight Metadata", systemImage: "magnifyingglass")
            }
            .accessibilityIdentifier("settings.systemSearch.rebuildSpotlight")
            .disabled(!spotlightMetadataIndexingEnabled)
        } header: {
            Text("Siri & System Search")
                .accessibilityIdentifier("settings.systemSearch.section")
        } footer: {
            Text("Siri, Shortcuts, Spotlight, Action Button, and widgets can open private OffRecord surfaces. Reading and searching entry text still happens inside the locked app.")
        }
    }

    @ViewBuilder
    private var dailyReminderSection: some View {
        Section {
            Toggle("Remind me to record", isOn: Binding(
                get: { reminderManager.isEnabled },
                set: { newValue in
                    if newValue {
                        reminderManager.requestPermissionIfNeeded { granted in
                            if granted {
                                reminderManager.isEnabled = true
                            } else {
                                showPermissionDeniedAlert = true
                            }
                        }
                    } else {
                        reminderManager.isEnabled = false
                    }
                }
            ))

            if reminderManager.isEnabled {
                DatePicker(
                    "Reminder time",
                    selection: Binding(
                        get: { reminderManager.reminderTime },
                        set: { reminderManager.reminderTime = $0 }
                    ),
                    displayedComponents: .hourAndMinute
                )
            }

            Toggle("Use Friday smart prompts", isOn: $reminderManager.usesFridaySmartPrompts)
                .accessibilityIdentifier("proactiveReflection.smartReminderToggle")

            if reminderManager.usesFridaySmartPrompts {
                Text("Reminder text stays privacy-safe and never includes names, topics, moods, regrets, or journal snippets.")
                    .font(OffRecordTypography.metadata)
                    .foregroundColor(OffRecordColor.textSecondary)
            }
        } header: {
            Text("Daily Reminder")
        } footer: {
            Text("OffRecord AI Journal sends one gentle notification each day at your chosen time.")
        }
    }

    @ViewBuilder
    private var iCloudSection: some View {
        Section {
            Toggle(isOn: $iCloudSyncEnabled) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(iCloudSyncEnabled && PersistenceController.isCloudAvailable ? OffRecordColor.surfaceBlue : OffRecordColor.surfaceWarm)
                            .frame(width: 36, height: 36)
                        Image(systemName: iCloudSyncEnabled && PersistenceController.isCloudAvailable ? "icloud.fill" : "icloud.slash")
                            .font(OffRecordTypography.bodyLarge)
                            .foregroundColor(iCloudSyncEnabled && PersistenceController.isCloudAvailable ? OffRecordColor.textSky : OffRecordColor.textTertiary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("iCloud Sync")
                            .font(OffRecordTypography.labelMedium)
                        Text(syncStatusText)
                            .font(OffRecordTypography.metadata)
                            .foregroundColor(OffRecordColor.textSecondary)
                    }
                }
            }
            .onChange(of: iCloudSyncEnabled) { _, newValue in
                PersistenceController.shared.setCloudSyncEnabled(newValue)
                showCloudSyncRestartAlert = true
            }

            if iCloudSyncEnabled && PersistenceController.isCloudAvailable {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(OffRecordColor.textSage)
                            .font(OffRecordTypography.metadata)
                        Text("Entries sync automatically via your personal iCloud")
                            .font(OffRecordTypography.metadata)
                            .foregroundColor(OffRecordColor.textSecondary)
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                            .foregroundColor(OffRecordColor.textSage)
                            .font(OffRecordTypography.metadata)
                        Text("Encrypted through your Apple ID")
                            .font(OffRecordTypography.metadata)
                            .foregroundColor(OffRecordColor.textSecondary)
                    }
                }
                .padding(.vertical, 4)
            } else if iCloudSyncEnabled && !PersistenceController.isCloudAvailable {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(OffRecordColor.textPeach)
                        .font(OffRecordTypography.metadata)
                    Text("iCloud unavailable")
                        .font(OffRecordTypography.metadata)
                        .foregroundColor(OffRecordColor.textSecondary)
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("iCloud Sync")
        } footer: {
            Text(iCloudSyncEnabled
                 ? (PersistenceController.isCloudAvailable
                    ? "Your data syncs securely through your personal iCloud account. Only you can access it."
                    : "Sign in to iCloud in iOS Settings to enable sync.")
                 : "Sync is off. Your entries are stored only on this device.")
        }
    }

    private var syncStatusText: String {
        if !iCloudSyncEnabled {
            return "Off — entries stay on this device only"
        }
        if PersistenceController.isCloudAvailable {
            return "Syncing across your devices"
        }
        return "iCloud not available — sign in to enable"
    }

    @ViewBuilder
    private var privacySection: some View {
        Section {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(OffRecordColor.surfaceSage)
                        .frame(width: 44, height: 44)
                    Image(systemName: "lock.shield.fill")
                        .font(OffRecordTypography.titleSmall)
                        .foregroundColor(OffRecordColor.textSage)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Privacy First")
                        .font(OffRecordTypography.labelMedium)
                    Text("Your data is encrypted and private")
                        .font(OffRecordTypography.metadata)
                        .foregroundColor(OffRecordColor.textSecondary)
                }
            }
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 12) {
                PrivacyInfoRow(
                    icon: "waveform",
                    title: "Apple Speech Transcription",
                    description: "Voice is converted to text using Apple Speech after you allow it. When online, audio may be processed by Apple."
                )
                PrivacyInfoRow(
                    icon: "server.rack",
                    title: "No Developer AI Servers",
                    description: "OffRecord does not send your journal data to developer servers or non-Apple AI services."
                )
                PrivacyInfoRow(
                    icon: "person.fill.xmark",
                    title: "No Account Required",
                    description: "No sign-up, no tracking, no analytics."
                )
            }
            .padding(.vertical, 8)

            if let privacyPolicyURL = OffRecordExternalLinks.privacyPolicyURL {
                Link(destination: privacyPolicyURL) {
                    Label("Privacy Policy", systemImage: "hand.raised.fill")
                }
            }
        } header: {
            Text("Privacy & Security")
        } footer: {
            Text("Your thoughts are yours alone. If enabled, sync uses your personal iCloud account, encrypted with your Apple ID.")
        }
    }

    @ViewBuilder
    private var backupSection: some View {
        Section {
            NavigationLink {
                BackupExportView(entries: startedEntries)
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(OffRecordColor.surfacePeach)
                            .frame(width: 36, height: 36)
                        Image(systemName: "square.and.arrow.up")
                            .font(OffRecordTypography.bodySmall)
                            .foregroundColor(OffRecordColor.textPeach)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Export Data")
                            .font(OffRecordTypography.bodySmall)
                        Text("JSON, Text, Markdown, CSV")
                            .font(OffRecordTypography.metadata)
                            .foregroundColor(OffRecordColor.textSecondary)
                    }
                }
            }

            NavigationLink {
                ImportBackupView()
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(OffRecordColor.surfaceBlue)
                            .frame(width: 36, height: 36)
                        Image(systemName: "square.and.arrow.down")
                            .font(OffRecordTypography.bodySmall)
                            .foregroundColor(OffRecordColor.textSky)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Import Backup")
                            .font(OffRecordTypography.bodySmall)
                        Text("Restore from JSON backup")
                            .font(OffRecordTypography.metadata)
                            .foregroundColor(OffRecordColor.textSecondary)
                    }
                }
            }
        } header: {
            Text("Backup & Export")
        } footer: {
            Text("Export your diary for safekeeping or import a previous backup.")
        }
    }

    @ViewBuilder
    private var storageSection: some View {
        Section {
            if isCalculatingStorage {
                HStack {
                    Text("Calculating...")
                    Spacer()
                    ProgressView()
                }
            } else {
                StorageRow(label: "Audio Recordings", bytes: audioStorageBytes, icon: "waveform", color: OffRecordColor.textAqua)
                StorageRow(label: "Photos", bytes: photoStorageBytes, icon: "photo", color: OffRecordColor.textBlush)
                StorageRow(label: "Database", bytes: databaseStorageBytes, icon: "cylinder", color: OffRecordColor.textPeach)

                HStack {
                    Text("Total")
                        .fontWeight(.semibold)
                    Spacer()
                    Text(formatBytes(audioStorageBytes + photoStorageBytes + databaseStorageBytes))
                        .fontWeight(.semibold)
                        .foregroundColor(OffRecordColor.textPrimary)
                }
            }
        } header: {
            HStack {
                Text("Storage")
                Spacer()
                Button {
                    calculateStorage()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(OffRecordTypography.metadata)
                }
            }
        } footer: {
            Text("Entries and photos sync through iCloud. Audio recordings stay on this device.")
        }
    }

    private func calculateStorage() {
        isCalculatingStorage = true
        DispatchQueue.global(qos: .userInitiated).async {
            let audioBytes = Self.directorySize(name: "Recordings")
            let photoBytes = Self.directorySize(name: "Photos")
            let dbBytes = Self.databaseSize()

            DispatchQueue.main.async {
                audioStorageBytes = audioBytes
                photoStorageBytes = photoBytes
                databaseStorageBytes = dbBytes
                isCalculatingStorage = false
            }
        }
    }

    private static func directorySize(name: String) -> Int64 {
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return 0 }
        let dir = base.appendingPathComponent(name)
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return files.reduce(Int64(0)) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return total + Int64(size)
        }
    }

    private static func databaseSize() -> Int64 {
        let fm = FileManager.default
        let possiblePaths: [URL] = [
            fm.containerURL(forSecurityApplicationGroupIdentifier: PersistenceController.appGroupIdentifier)?
                .appendingPathComponent("OffRecord.sqlite"),
            NSPersistentCloudKitContainer.defaultDirectoryURL()
                .appendingPathComponent("OffRecord.sqlite")
        ].compactMap { $0 }

        for path in possiblePaths {
            // sqlite has companion -wal and -shm files
            let extensions = ["", "-wal", "-shm"]
            let total = extensions.reduce(Int64(0)) { sum, ext in
                let file = URL(fileURLWithPath: path.path + ext)
                let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                return sum + Int64(size)
            }
            if total > 0 { return total }
        }
        return 0
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    @ViewBuilder
    private var aboutSection: some View {
        Section(header: Text("About")) {
            HStack {
                Text("Version")
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    .foregroundColor(OffRecordColor.textSecondary)
            }

            HStack {
                Text("Total Entries")
                Spacer()
                Text("\(totalEntriesCount)")
                    .foregroundColor(OffRecordColor.textSecondary)
            }
        }
    }

    private var totalEntriesCount: Int {
        settingsStats.entryCount
    }

    private var years: [Int] {
        settingsStats.availableYears
    }

    private var currentMonth: Int {
        Calendar.current.component(.month, from: Date())
    }

    private var currentQuarter: Int {
        (Calendar.current.component(.month, from: Date()) - 1) / 3 + 1
    }

    private func monthName(_ month: Int) -> String {
        var components = DateComponents()
        components.month = month
        if let date = Calendar.current.date(from: components) {
            return Self.monthFormatter.string(from: date)
        }
        return ""
    }

    private func generatePDF() {
        #if os(iOS)
        let year = selectedYear ?? years.last!
        isExporting = true
        let token = PerformanceSignposts.begin("SettingsPDFExport")

        // Determine date range based on export period
        let dateRange: PDFExportService.DateRange
        let periodTitle: String

        switch selectedExportPeriod {
        case .monthly:
            let month = selectedMonth ?? currentMonth
            dateRange = .month(year: year, month: month)
            periodTitle = "\(monthName(month)) \(year)"
        case .quarterly:
            let quarter = selectedMonth ?? currentQuarter
            dateRange = .quarter(year: year, quarter: quarter)
            periodTitle = "Q\(quarter) \(year)"
        case .yearly:
            dateRange = .year(year)
            periodTitle = String(year)
        }

        Task {
            do {
                let exportEntries = startedEntries
                let baseEntries: [DiaryEntry]
                if starredOnly {
                    baseEntries = exportEntries.filter { $0.isStarred }
                } else {
                    baseEntries = exportEntries
                }

                let url = try PDFExportService.generatePDF(
                    for: baseEntries,
                    dateRange: dateRange,
                    periodTitle: periodTitle,
                    paperSize: selectedPaperSize,
                    authorName: authorName.isEmpty ? nil : authorName,
                    authorDescription: authorDescription.isEmpty ? nil : authorDescription
                )
                await MainActor.run {
                    exportURL = url
                    isExporting = false
                    PerformanceSignposts.end(token)
                }
            } catch {
                await MainActor.run {
                    exportError = error.localizedDescription
                    isExporting = false
                    PerformanceSignposts.end(token)
                }
            }
        }
        #else
        exportError = "PDF export is available on iOS."
        #endif
    }

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        return formatter
    }()

    @MainActor
    private func refreshSettingsStats() async {
        let token = PerformanceSignposts.begin("SettingsSummaryRefresh")
        let snapshots = startedEntries.journalSnapshots
        let nextStats = await JournalAnalyticsWorker.shared.makeStats(
            from: snapshots,
            now: Date(),
            weeklyTarget: goalManager.weeklyTarget,
            goalEnabled: goalManager.isEnabled
        )
        guard !Task.isCancelled else {
            PerformanceSignposts.end(token)
            return
        }
        settingsStats = nextStats
        PerformanceSignposts.end(token)
    }
}

struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}

#if os(iOS)
import UIKit

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

// MARK: - Theme Button

struct ThemeButton: View {
    let theme: AppTheme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Color.clear
                        .frame(width: 48, height: 48)
                        .offRecordGlassControl(tint: isSelected ? theme.accentColor : nil, in: Circle(), fallbackFill: theme.accentColor.opacity(0.2))
                    
                    Circle()
                        .fill(theme.accentColor.opacity(isSelected ? 1 : 0.8))
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: theme.icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(theme.swatchForegroundColor)
                }
                .overlay {
                    if isSelected {
                        Circle()
                            .stroke(theme.accentColor, lineWidth: 2)
                            .frame(width: 52, height: 52)
                    }
                }
                
                Text(theme.rawValue)
                    .font(OffRecordTypography.metadata)
                    .foregroundColor(isSelected ? theme.readableAccentColor : OffRecordColor.textSecondary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Storage Row

struct StorageRow: View {
    let label: String
    let bytes: Int64
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(OffRecordTypography.metadata)
                    .foregroundColor(color)
            }
            Text(label)
            Spacer()
            Text(formattedSize)
                .foregroundColor(OffRecordColor.textSecondary)
        }
    }

    private var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Privacy Info Row

struct PrivacyInfoRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(OffRecordTypography.bodySmall)
                .foregroundColor(OffRecordColor.textSage)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(OffRecordTypography.labelMedium)
                Text(description)
                    .font(OffRecordTypography.metadata)
                    .foregroundColor(OffRecordColor.textSecondary)
            }
        }
    }
}
