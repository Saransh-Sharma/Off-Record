import SwiftUI
import CoreData
import AppIntents
#if os(iOS)
import UIKit
#endif

struct SettingsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject private var reminderManager = ReminderManager.shared
    @ObservedObject private var lockManager = AppLockManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var goalManager = GoalManager.shared
    @ObservedObject private var semanticMemory = SemanticMemoryIndexController.shared
    @ObservedObject private var weeklyReflection = WeeklyReflectionController.shared

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \DiaryEntry.date, ascending: true)],
        predicate: DiaryEntry.startedEntryPredicate,
        animation: .default)
    private var entries: FetchedResults<DiaryEntry>

    @State private var showPermissionDeniedAlert = false
    @State private var showWeeklyNotificationPermissionDeniedAlert = false
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
        GeometryReader { proxy in
            ScrollView {
                let columns = settingsColumns(for: proxy.size.width)

                VStack(alignment: .leading, spacing: OffRecordSpacing.section) {
                    SettingsGroup(
                        title: "Journal & Reminders",
                        subtitle: "Tune the habit-building parts of OffRecord without exposing journal content."
                    ) {
                        LazyVGrid(columns: columns, spacing: OffRecordSpacing.lg) {
                            journalingGoalSection
                            dailyReminderSection
                            weeklyReflectionSection
                        }
                    }

                    SettingsGroup(
                        title: "Privacy & AI",
                        subtitle: "Control local intelligence, search surfaces, and device-level privacy."
                    ) {
                        LazyVGrid(columns: columns, spacing: OffRecordSpacing.lg) {
                            securitySection
                            localAIPrivacySection
                            semanticMemorySection
                            systemSearchSection
                        }
                    }

                    SettingsGroup(
                        title: "Data & Export",
                        subtitle: "Export, back up, sync, and review what OffRecord stores on this device."
                    ) {
                        LazyVGrid(columns: columns, spacing: OffRecordSpacing.lg) {
                            exportSection
                            backupSection
                            iCloudSection
                            storageSection
                        }
                    }

                    SettingsGroup(title: "Appearance") {
                        LazyVGrid(columns: columns, spacing: OffRecordSpacing.lg) {
                            appearanceSection
                        }
                    }

                    SettingsGroup(title: "About") {
                        LazyVGrid(columns: columns, spacing: OffRecordSpacing.lg) {
                            privacySection
                            aboutSection
                        }
                    }
                }
                .frame(maxWidth: contentMaxWidth(for: proxy.size.width))
                .frame(maxWidth: .infinity)
                .padding(.horizontal, OffRecordSpacing.screenX)
                .padding(.vertical, OffRecordSpacing.screenY)
            }
        }
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
            Text("Please enable notifications for OffRecord in Settings to receive daily reminders.")
        }
        .alert("Weekly Notifications Disabled", isPresented: $showWeeklyNotificationPermissionDeniedAlert) {
            #if os(iOS)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                    UIApplication.shared.open(url)
                } else if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            #endif
            Button("OK", role: .cancel) { }
        } message: {
            Text("Enable notifications for OffRecord to receive your private weekly reflection reminder.")
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
            Text("Restart OffRecord for the iCloud sync change to take effect.")
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

    private func settingsColumns(for width: CGFloat) -> [GridItem] {
        guard width >= 760, !dynamicTypeSize.isAccessibilitySize else {
            return [GridItem(.flexible(), spacing: OffRecordSpacing.lg)]
        }

        return [
            GridItem(.flexible(), spacing: OffRecordSpacing.lg),
            GridItem(.flexible(), spacing: OffRecordSpacing.lg)
        ]
    }

    private func contentMaxWidth(for width: CGFloat) -> CGFloat? {
        width >= 900 ? 980 : nil
    }

    @ViewBuilder
    private var exportSection: some View {
        SettingsCard(
            title: "PDF Export",
            subtitle: "Create a readable PDF for a month, quarter, or year.",
            footer: "Your name and description appear only on the exported PDF cover page.",
            systemImage: "doc.richtext",
            tint: OffRecordColor.textSky,
            fill: OffRecordColor.surfaceBlue
        ) {
            TextField("Your name", text: $authorName)
                .textFieldStyle(.roundedBorder)
            TextField("Description (optional)", text: $authorDescription)
                .textFieldStyle(.roundedBorder)

            if years.isEmpty {
                SettingsRow(
                    systemImage: "tray",
                    title: "No entries to export yet",
                    subtitle: "Record a few private entries first, then come back to create a PDF.",
                    tint: OffRecordColor.textSky
                )
            } else {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: OffRecordSpacing.md) {
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
                    }
                    .padding(.top, OffRecordSpacing.sm)
                } label: {
                    Label("Export options", systemImage: "slider.horizontal.3")
                        .font(OffRecordTypography.labelMedium)
                        .foregroundStyle(OffRecordColor.textSky)
                }

                Button {
                    generatePDF()
                } label: {
                    HStack(spacing: OffRecordSpacing.sm) {
                        if isExporting {
                            ProgressView()
                                .tint(OffRecordColor.textInverse)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                        }
                        Text(isExporting ? "Exporting PDF..." : "Export as PDF")
                    }
                }
                .buttonStyle(SettingsPrimaryButtonStyle())
                .disabled(isExporting)
            }
        }
    }

    @ViewBuilder
    private var appearanceSection: some View {
        SettingsCard(
            title: "Accent Color",
            subtitle: "Choose the accent used for buttons, highlights, and selected states.",
            systemImage: "paintpalette",
            tint: themeManager.selectedTheme.readableAccentColor,
            fill: OffRecordColor.surfacePrimary
        ) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: OffRecordSpacing.md)], spacing: OffRecordSpacing.md) {
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
        }
    }

    @ViewBuilder
    private var journalingGoalSection: some View {
        SettingsCard(
            title: "Journaling Goal",
            subtitle: "Set a weekly target to build a consistent habit.",
            systemImage: "target",
            tint: OffRecordColor.textAqua,
            fill: OffRecordColor.surfaceMint
        ) {
            Toggle("Enable weekly goal", isOn: $goalManager.isEnabled)

            if goalManager.isEnabled {
                Stepper("Target: \(goalManager.weeklyTarget) entries/week", value: $goalManager.weeklyTarget, in: 1...7)

                Toggle("Notify when goal reached", isOn: $goalManager.notifyOnGoal)
            }
        }
    }

    @ViewBuilder
    private var securitySection: some View {
        SettingsCard(
            title: "Privacy Lock",
            subtitle: "Require device authentication before opening your journal.",
            systemImage: "lock.shield.fill",
            tint: OffRecordColor.textSage,
            fill: OffRecordColor.surfaceSage
        ) {
            Toggle("Require \(lockManager.biometryTypeName) to open OffRecord", isOn: $lockManager.isEnabled)

            if lockManager.isEnabled {
                Text("Your journal locks when you leave the app. OffRecord never sees or stores your \(lockManager.biometryTypeName).")
                    .font(OffRecordTypography.metadata)
                    .foregroundColor(OffRecordColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !lockManager.biometricsAvailable {
                Text("If \(lockManager.biometryTypeName) is unavailable, iOS will use your device passcode.")
                    .font(OffRecordTypography.metadata)
                    .foregroundColor(OffRecordColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var localAIPrivacySection: some View {
        SettingsCard(
            title: "Local AI & Offline Privacy",
            subtitle: "Private intelligence stays local unless you allow Apple Speech transcription.",
            footer: "Optional iCloud Sync is separate and uses your personal Apple iCloud account, not an OffRecord server.",
            systemImage: "cpu.fill",
            tint: OffRecordColor.textLavender,
            fill: OffRecordColor.surfaceLavender
        ) {
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
        }
    }

    @ViewBuilder
    private var semanticMemorySection: some View {
        SettingsCard(
            title: "Semantic Memory",
            subtitle: "Derived local search memory for Friday and journal recall.",
            footer: "Embeddings are derived locally from journal entries and are not synced to iCloud.",
            systemImage: "brain.head.profile",
            tint: OffRecordColor.textLavender,
            fill: OffRecordColor.surfacePrimary
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Semantic Memory")
                            .font(OffRecordTypography.labelMedium)
                        Text(semanticMemory.statusMessage)
                            .font(OffRecordTypography.metadata)
                            .foregroundColor(OffRecordColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
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

                SettingsRow(systemImage: "number", title: "Indexed chunks", tint: OffRecordColor.textLavender) {
                    Text("\(semanticMemory.chunkCount)")
                        .font(OffRecordTypography.bodySmall)
                        .foregroundColor(OffRecordColor.textPrimary)
                        .accessibilityIdentifier("semanticMemory.chunkCount")
                }

                if semanticMemory.usesFallbackEmbeddings {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("Sentence embeddings were unavailable, so OffRecord is using a local lexical fallback until rebuild succeeds.")
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
                .buttonStyle(SettingsSecondaryButtonStyle(tint: OffRecordColor.textLavender, fill: OffRecordColor.surfaceLavender))
                .accessibilityIdentifier("semanticMemory.rebuild")
                .disabled(semanticMemory.isBuilding)

                Button(role: .destructive) {
                    showDeleteSemanticIndexConfirm = true
                } label: {
                    Label("Delete Local Semantic Index", systemImage: "trash")
                }
                .buttonStyle(SettingsSecondaryButtonStyle(tint: OffRecordColor.textCoral, fill: OffRecordColor.backgroundBlushTint))
                .accessibilityIdentifier("semanticMemory.delete")
                .disabled(semanticMemory.isBuilding && semanticMemory.chunkCount == 0)
            }
            .accessibilityIdentifier("semanticMemory.section")
        }
    }

    @ViewBuilder
    private var systemSearchSection: some View {
        SettingsCard(
            title: "Siri & System Search",
            subtitle: "Let system surfaces open private OffRecord destinations without exposing journal text.",
            footer: "Reading and searching entry text still happens inside the locked app.",
            systemImage: "magnifyingglass",
            tint: OffRecordColor.textSky,
            fill: OffRecordColor.surfacePrimary
        ) {
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
            .buttonStyle(SettingsSecondaryButtonStyle(tint: OffRecordColor.textSky, fill: OffRecordColor.surfaceBlue))
            .accessibilityIdentifier("settings.systemSearch.rebuildSpotlight")
            .disabled(!spotlightMetadataIndexingEnabled)
        }
        .accessibilityIdentifier("settings.systemSearch.section")
    }

    @ViewBuilder
    private var dailyReminderSection: some View {
        SettingsCard(
            title: "Daily Reminder",
            subtitle: "Send one privacy-safe notification at your chosen time.",
            systemImage: "bell.badge",
            tint: OffRecordColor.textPeach,
            fill: OffRecordColor.surfacePeach
        ) {
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
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var weeklyReflectionSection: some View {
        SettingsCard(
            title: "Weekly Reflection",
            subtitle: "Summarize selected journal entries locally and optionally remind you weekly.",
            footer: "Notifications never include journal content, themes, moods, names, or quotes.",
            systemImage: "calendar.badge.clock",
            tint: OffRecordColor.textAqua,
            fill: OffRecordColor.surfaceMint
        ) {
            Toggle("Enable weekly reflection", isOn: Binding(
                get: { weeklyReflection.settings.isEnabled },
                set: { value in weeklyReflection.updateSettings { $0.isEnabled = value } }
            ))
            .accessibilityIdentifier("weeklyReflection.settings.enabled")

            if weeklyReflection.settings.isEnabled {
                Picker("Reflection day", selection: Binding(
                    get: { weeklyReflection.settings.reminderWeekday },
                    set: { value in weeklyReflection.updateSettings { $0.reminderWeekday = value } }
                )) {
                    Text("Sunday").tag(1)
                    Text("Monday").tag(2)
                    Text("Tuesday").tag(3)
                    Text("Wednesday").tag(4)
                    Text("Thursday").tag(5)
                    Text("Friday").tag(6)
                    Text("Saturday").tag(7)
                }

                DatePicker(
                    "Reminder time",
                    selection: Binding(
                        get: {
                            var components = DateComponents()
                            components.hour = weeklyReflection.settings.reminderHour
                            components.minute = weeklyReflection.settings.reminderMinute
                            return Calendar.current.date(from: components) ?? Date()
                        },
                        set: { date in
                            let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                            weeklyReflection.updateSettings {
                                $0.reminderHour = components.hour ?? 19
                                $0.reminderMinute = components.minute ?? 0
                            }
                        }
                    ),
                    displayedComponents: .hourAndMinute
                )

                Toggle("Show Home card", isOn: Binding(
                    get: { weeklyReflection.settings.showHomeCard },
                    set: { value in weeklyReflection.updateSettings { $0.showHomeCard = value } }
                ))

                Toggle("Send notification", isOn: Binding(
                    get: { weeklyReflection.settings.sendNotification },
                    set: { value in handleWeeklyNotificationToggle(value) }
                ))

                Label("Processing: Local only", systemImage: "lock.shield.fill")
                    .font(OffRecordTypography.metadata)
                    .foregroundColor(OffRecordColor.textSage)

                Text("Weekly reflections use selected journal entries on this device. You can hide entries inside a report and regenerate without changing the original entry.")
                    .font(OffRecordTypography.metadata)
                    .foregroundColor(OffRecordColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func handleWeeklyNotificationToggle(_ isEnabled: Bool) {
        guard isEnabled else {
            weeklyReflection.updateSettings { $0.sendNotification = false }
            return
        }

        Task {
            let granted = await WeeklyReflectionNotificationScheduler.requestPermissionIfNeeded()
            await MainActor.run {
                weeklyReflection.updateSettings { $0.sendNotification = granted }
                if !granted {
                    showWeeklyNotificationPermissionDeniedAlert = true
                }
            }
        }
    }

    @ViewBuilder
    private var iCloudSection: some View {
        SettingsCard(
            title: "iCloud Sync",
            subtitle: syncStatusText,
            footer: iCloudSyncEnabled
                ? (PersistenceController.isCloudAvailable
                   ? "Your data syncs securely through your personal iCloud account. Only you can access it."
                   : "Sign in to iCloud in iOS Settings to enable sync.")
                : "Sync is off. Your entries are stored only on this device.",
            systemImage: iCloudSyncEnabled && PersistenceController.isCloudAvailable ? "icloud.fill" : "icloud.slash",
            tint: iCloudSyncEnabled && PersistenceController.isCloudAvailable ? OffRecordColor.textSky : OffRecordColor.textTertiary,
            fill: OffRecordColor.surfaceBlue
        ) {
            Toggle(isOn: $iCloudSyncEnabled) {
                Text("Sync entries with iCloud")
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
                            .accessibilityHidden(true)
                        Text("Entries sync automatically via your personal iCloud")
                            .font(OffRecordTypography.metadata)
                            .foregroundColor(OffRecordColor.textSecondary)
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                            .foregroundColor(OffRecordColor.textSage)
                            .font(OffRecordTypography.metadata)
                            .accessibilityHidden(true)
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
                        .accessibilityHidden(true)
                    Text("iCloud unavailable")
                        .font(OffRecordTypography.metadata)
                        .foregroundColor(OffRecordColor.textSecondary)
                }
                .padding(.vertical, 4)
            }
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
        SettingsCard(
            title: "Privacy & Security",
            subtitle: "A quick summary of OffRecord's privacy posture.",
            footer: "Your thoughts are yours alone. If enabled, sync uses your personal iCloud account, encrypted with your Apple ID.",
            systemImage: "lock.shield.fill",
            tint: OffRecordColor.textSage,
            fill: OffRecordColor.surfaceSage
        ) {
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
                .buttonStyle(SettingsSecondaryButtonStyle(tint: OffRecordColor.textSage, fill: OffRecordColor.surfacePrimary))
            }
        }
    }

    @ViewBuilder
    private var backupSection: some View {
        SettingsCard(
            title: "Backup & Export",
            subtitle: "Create portable backups or restore a previous archive.",
            footer: "Encrypted backups are password protected. OffRecord cannot recover a forgotten backup password.",
            systemImage: "archivebox",
            tint: OffRecordColor.textSky,
            fill: OffRecordColor.surfacePrimary
        ) {
            NavigationLink {
                BackupExportView(entries: startedEntries)
            } label: {
                SettingsActionRow(
                    systemImage: "square.and.arrow.up",
                    title: "Export Data",
                    subtitle: "JSON, encrypted backup, Text, Markdown, CSV",
                    tint: OffRecordColor.textSky
                )
            }

            NavigationLink {
                ImportBackupView()
            } label: {
                SettingsActionRow(
                    systemImage: "square.and.arrow.down",
                    title: "Import Backup",
                    subtitle: "Restore JSON or encrypted backup files",
                    tint: OffRecordColor.textSky
                )
            }
        }
    }

    @ViewBuilder
    private var storageSection: some View {
        SettingsCard(
            title: "Storage",
            subtitle: "See what OffRecord is storing on this device.",
            footer: "Entries and photos sync through iCloud when enabled. Audio recordings stay on this device.",
            systemImage: "internaldrive",
            tint: OffRecordColor.textAqua,
            fill: OffRecordColor.surfacePrimary
        ) {
            if isCalculatingStorage {
                SettingsRow(systemImage: "hourglass", title: "Calculating storage", tint: OffRecordColor.textAqua) {
                    ProgressView()
                }
            } else {
                let total = audioStorageBytes + photoStorageBytes + databaseStorageBytes
                StorageRow(label: "Audio Recordings", bytes: audioStorageBytes, totalBytes: total, icon: "waveform", color: OffRecordColor.textAqua)
                StorageRow(label: "Photos", bytes: photoStorageBytes, totalBytes: total, icon: "photo", color: OffRecordColor.textBlush)
                StorageRow(label: "Database", bytes: databaseStorageBytes, totalBytes: total, icon: "cylinder", color: OffRecordColor.textPeach)

                SettingsRow(systemImage: "sum", title: "Total", tint: OffRecordColor.textBrand) {
                    Text(formatBytes(total))
                        .font(OffRecordTypography.labelMedium)
                        .foregroundColor(OffRecordColor.textPrimary)
                        .monospacedDigit()
                }
            }

            Button {
                calculateStorage()
            } label: {
                Label("Refresh storage", systemImage: "arrow.clockwise")
            }
            .buttonStyle(SettingsSecondaryButtonStyle(tint: OffRecordColor.textAqua, fill: OffRecordColor.surfaceMint))
            .accessibilityLabel("Refresh storage")
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
        SettingsCard(
            title: "About OffRecord",
            subtitle: "App version and local journal summary.",
            systemImage: "info.circle",
            tint: OffRecordColor.textBrand,
            fill: OffRecordColor.surfacePrimary
        ) {
            SettingsRow(systemImage: "number", title: "Version", tint: OffRecordColor.textBrand) {
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    .font(OffRecordTypography.bodySmall)
                    .foregroundColor(OffRecordColor.textPrimary)
            }

            SettingsRow(systemImage: "book.pages", title: "Total entries", tint: OffRecordColor.textBrand) {
                Text("\(totalEntriesCount)")
                    .font(OffRecordTypography.bodySmall)
                    .foregroundColor(OffRecordColor.textPrimary)
                    .monospacedDigit()
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
