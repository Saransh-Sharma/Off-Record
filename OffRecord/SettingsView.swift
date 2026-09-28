import SwiftUI
import TranscriptionKit
import CoreData
import AppIntents
import os.log
#if os(iOS)
import UIKit
#endif

private let settingsLogger = Logger(subsystem: "com.singularity.offrecord", category: "Settings")

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
    @ObservedObject private var health = HealthStateOfMindWriter.shared
    @State private var searchText = ""

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
            ScrollViewReader { scrollProxy in
            ScrollView {
                let metrics = OffRecordAdaptiveMetrics(
                    width: proxy.size.width,
                    horizontalSizeClass: horizontalSizeClass
                )
                let columns = metrics.settingsColumns(dynamicTypeSize: dynamicTypeSize)

                VStack(alignment: .leading, spacing: OffRecordSpacing.section) {
                    if !isSearching {
                        PrivacyAtAGlanceCard(rows: privacyGlanceRows) { target in
                            withOffRecordAnimation(OffRecordMotion.gentle) {
                                scrollProxy.scrollTo(target, anchor: .top)
                            }
                        }
                    }

                    settingsGroup(
                        title: "Journal & Reminders",
                        columns: columns,
                        items: [
                            .init(id: "goal", keywords: "weekly goal journaling target habit", view: AnyView(journalingGoalSection)),
                            .init(id: "reminder", keywords: "daily reminder notification time", view: AnyView(dailyReminderSection)),
                            .init(id: "weekly", keywords: "weekly reflection report notification", view: AnyView(weeklyReflectionSection))
                        ]
                    )

                    settingsGroup(
                        title: "Privacy & AI",
                        columns: columns,
                        items: [
                            .init(id: "lock", keywords: "lock face id touch id passcode privacy security", view: AnyView(securitySection)),
                            .init(id: "localAI", keywords: "on-device ai transcription speech offline privacy", view: AnyView(localAIPrivacySection)),
                            .init(id: "health", keywords: "apple health state of mind mood sync", view: AnyView(healthSection)),
                            .init(id: "semantic", keywords: "search index meaning friday rebuild delete", view: AnyView(semanticMemorySection)),
                            .init(id: "spotlight", keywords: "siri spotlight system search shortcuts", view: AnyView(systemSearchSection))
                        ]
                    )

                    settingsGroup(
                        title: "Data & Export",
                        columns: columns,
                        items: [
                            .init(id: "export", keywords: "export pdf print", view: AnyView(exportSection)),
                            .init(id: "backup", keywords: "backup encrypted json markdown csv import restore", view: AnyView(backupSection)),
                            .init(id: "icloud", keywords: "icloud sync cloud devices", view: AnyView(iCloudSection)),
                            .init(id: "storage", keywords: "storage space audio photos delete", view: AnyView(storageSection))
                        ]
                    )

                    settingsGroup(
                        title: "Appearance",
                        columns: columns,
                        items: [
                            .init(id: "theme", keywords: "theme appearance dark light color accent", view: AnyView(appearanceSection))
                        ]
                    )

                    settingsGroup(
                        title: "About",
                        columns: columns,
                        items: [
                            .init(id: "privacyPolicy", keywords: "privacy policy data not collected", view: AnyView(privacySection)),
                            .init(id: "about", keywords: "about version support", view: AnyView(aboutSection))
                        ]
                    )

                    if isSearching && !hasSearchResults {
                        ContentUnavailableView.search(text: searchText)
                    }
                }
                .frame(maxWidth: metrics.pageMaxWidth)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, metrics.pageHorizontalPadding)
                .padding(.vertical, OffRecordSpacing.screenY)
            }
            }
        }
        .background(OffRecordAppBackground())
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search")
        .onAppear {
            calculateStorage()
        }
        .task(id: "\(entriesSignature)-\(goalManager.weeklyTarget)-\(goalManager.isEnabled)") {
            await refreshSettingsStats()
        }
        .navigationTitle("Settings")
        .alert("Notifications Are Off", isPresented: $showPermissionDeniedAlert) {
            #if os(iOS)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            #endif
            Button("OK", role: .cancel) { }
        } message: {
            Text("Turn on notifications for OffRecord in Settings to get reminders.")
        }
        .alert("Notifications Are Off", isPresented: $showWeeklyNotificationPermissionDeniedAlert) {
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
            Text("Turn on notifications for OffRecord in Settings to get the weekly reminder.")
        }
        .alert("Couldn’t Export", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(exportError ?? "")
        }
        .alert("Restart OffRecord", isPresented: $showCloudSyncRestartAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Close and reopen OffRecord to apply the iCloud change.")
        }
        .alert("Delete Search Index?", isPresented: $showDeleteSemanticIndexConfirm) {
            Button("Delete Index", role: .destructive) {
                semanticMemory.deleteIndex()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Your entries aren’t affected. You can rebuild it anytime.")
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

    // MARK: - Search & glance

    private struct SettingsItem: Identifiable {
        let id: String
        let keywords: String
        let view: AnyView
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func matches(_ item: SettingsItem) -> Bool {
        guard isSearching else { return true }
        let terms = searchText.lowercased().split(separator: " ")
        let haystack = item.keywords.lowercased()
        return terms.allSatisfy { haystack.contains($0) }
    }

    private var hasSearchResults: Bool {
        allSearchKeywords.contains { keywords in
            let terms = searchText.lowercased().split(separator: " ")
            return terms.allSatisfy { keywords.contains($0) }
        }
    }

    private var allSearchKeywords: [String] {
        [
            "weekly goal journaling target habit", "daily reminder notification time", "weekly reflection report notification",
            "lock face id touch id passcode privacy security", "on-device ai transcription speech offline privacy",
            "apple health state of mind mood sync", "search index meaning friday rebuild delete",
            "siri spotlight system search shortcuts", "export pdf print", "backup encrypted json markdown csv import restore",
            "icloud sync cloud devices", "storage space audio photos delete", "theme appearance dark light color accent",
            "privacy policy data not collected", "about version support"
        ]
    }

    @ViewBuilder
    private func settingsGroup(
        title: String,
        columns: [GridItem],
        items: [SettingsItem]
    ) -> some View {
        let visible = items.filter(matches)
        if !visible.isEmpty {
            SettingsGroup(title: title) {
                LazyVGrid(columns: columns, spacing: OffRecordSpacing.lg) {
                    ForEach(visible) { item in
                        item.view.id(item.id)
                    }
                }
            }
        }
    }

    private var privacyGlanceRows: [PrivacyGlanceRow] {
        [
            PrivacyGlanceRow(
                id: "lock",
                systemImage: "lock.shield.fill",
                title: "Lock",
                status: lockManager.isEnabled ? "On" : "Off",
                isPositive: lockManager.isEnabled
            ),
            PrivacyGlanceRow(
                id: "localAI",
                systemImage: "cpu.fill",
                title: "AI & Transcription",
                status: "On-device",
                isPositive: true
            ),
            PrivacyGlanceRow(
                id: "icloud",
                systemImage: iCloudSyncEnabled ? "icloud.fill" : "icloud.slash",
                title: "iCloud Sync",
                status: iCloudSyncEnabled ? "Your iCloud" : "Off",
                isPositive: true
            ),
            PrivacyGlanceRow(
                id: "health",
                systemImage: "heart.text.square.fill",
                title: "Apple Health",
                status: health.isEnabled ? "Moods only" : "Off",
                isPositive: true
            ),
            PrivacyGlanceRow(
                id: "spotlight",
                systemImage: "magnifyingglass",
                title: "Spotlight",
                status: spotlightMetadataIndexingEnabled ? "Dates and moods only" : "Off",
                isPositive: true
            )
        ]
    }

    private var healthSection: some View {
        SettingsCard(
            title: "Apple Health",
            footer: "Only the mood and time are saved. OffRecord never reads Health data.",
            systemImage: "heart.text.square.fill",
            tint: OffRecordColor.textBlush,
            fill: OffRecordColor.surfaceBlush
        ) {
            Toggle("Save Moods to Health", isOn: Binding(
                get: { health.isEnabled },
                set: { newValue in
                    Task { await health.setEnabled(newValue) }
                }
            ))
            .disabled(!health.isAvailable)
            .accessibilityIdentifier("settings.health.toggle")

            if !health.isAvailable {
                Text("Apple Health isn’t available on this \(DeviceNoun.current).")
                    .font(OffRecordTypography.metadata)
                    .foregroundStyle(OffRecordColor.textSecondary)
            } else if let error = health.lastError {
                Text(error)
                    .font(OffRecordTypography.metadata)
                    .foregroundStyle(OffRecordColor.textCoral)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var exportSection: some View {
        SettingsCard(
            title: "PDF Export",
            footer: "Name and subtitle appear on the cover only.",
            systemImage: "doc.richtext",
            tint: OffRecordColor.textSky,
            fill: OffRecordColor.surfaceBlue
        ) {
            TextField("Name", text: $authorName)
                .textFieldStyle(.roundedBorder)
            TextField("Subtitle (optional)", text: $authorDescription)
                .textFieldStyle(.roundedBorder)

            if years.isEmpty {
                SettingsRow(
                    systemImage: "tray",
                    title: "No entries to export yet.",
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
                                Text("Q1 (Jan–Mar)").tag(1)
                                Text("Q2 (Apr–Jun)").tag(2)
                                Text("Q3 (Jul–Sep)").tag(3)
                                Text("Q4 (Oct–Dec)").tag(4)
                            }
                        }

                        Picker("Paper Size", selection: $selectedPaperSize) {
                            ForEach(PDFPaperSize.allCases) { size in
                                Text(size.rawValue).tag(size)
                            }
                        }

                        Toggle("Starred Only", isOn: $starredOnly)
                    }
                    .padding(.top, OffRecordSpacing.sm)
                } label: {
                    Label("Options", systemImage: "slider.horizontal.3")
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
                        Text(isExporting ? "Exporting…" : "Export PDF")
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
            title: "Theme",
            footer: "System matches your \(DeviceNoun.current)’s appearance.",
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
                        withOffRecordAnimation(OffRecordMotion.fade) {
                            themeManager.selectedTheme = theme
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var journalingGoalSection: some View {
        SettingsCard(
            title: "Weekly Goal",
            systemImage: "target",
            tint: OffRecordColor.textAqua,
            fill: OffRecordColor.surfaceMint
        ) {
            Toggle("Weekly Goal", isOn: $goalManager.isEnabled)

            if goalManager.isEnabled {
                Stepper(value: $goalManager.weeklyTarget, in: 1...7) {
                    Text("^[\(goalManager.weeklyTarget) day](inflect: true) a week")
                }

                Toggle("Notify When Reached", isOn: $goalManager.notifyOnGoal)
            }
        }
    }

    @ViewBuilder
    private var securitySection: some View {
        SettingsCard(
            title: "Lock",
            footer: "Locks when you leave the app. Falls back to your passcode.",
            systemImage: "lock.shield.fill",
            tint: OffRecordColor.textSage,
            fill: OffRecordColor.surfaceSage
        ) {
            Toggle("Require \(lockManager.biometryTypeName)", isOn: $lockManager.isEnabled)
        }
    }

    @ViewBuilder
    private var localAIPrivacySection: some View {
        SettingsCard(
            title: "On-Device AI",
            footer: "iCloud Sync uses your own iCloud account.",
            systemImage: "cpu.fill",
            tint: OffRecordColor.textLavender,
            fill: OffRecordColor.surfaceLavender
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Friday, search, and transcription run on this \(DeviceNoun.current) and work offline.")
                    .font(OffRecordTypography.bodySmall)
                    .foregroundColor(OffRecordColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle("Transcription", isOn: $appleSpeechProcessingConsentGranted)
                    .accessibilityIdentifier("settings.privacy.appleSpeechConsentToggle")
                    .onChange(of: appleSpeechProcessingConsentGranted) { _, granted in
                        if granted {
                            SpeechTranscriptionConsent.grantAppleSpeechProcessing()
                        } else {
                            SpeechTranscriptionConsent.revokeAppleSpeechProcessing()
                        }
                    }

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
            title: "Search Index",
            footer: "Lets search and Friday find entries by meaning. Built on this \(DeviceNoun.current), never synced.",
            systemImage: "brain.head.profile",
            tint: OffRecordColor.textLavender,
            fill: OffRecordColor.surfacePrimary
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Status")
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

                SettingsRow(systemImage: "number", title: String(localized: "Indexed Passages", comment: "How many pieces of the journal the search index holds"), tint: OffRecordColor.textLavender) {
                    Text(verbatim: "\(semanticMemory.chunkCount)")
                        .font(OffRecordTypography.bodySmall)
                        .foregroundColor(OffRecordColor.textPrimary)
                        .accessibilityIdentifier("semanticMemory.chunkCount")
                }

                if semanticMemory.usesFallbackEmbeddings {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("Running in basic mode. Rebuild to fix.")
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
                    Label("Rebuild Index", systemImage: "arrow.clockwise")
                }
                .buttonStyle(SettingsSecondaryButtonStyle(tint: OffRecordColor.textLavender, fill: OffRecordColor.surfaceLavender))
                .accessibilityIdentifier("semanticMemory.rebuild")
                .disabled(semanticMemory.isBuilding)

                Button(role: .destructive) {
                    showDeleteSemanticIndexConfirm = true
                } label: {
                    Label("Delete Index", systemImage: "trash")
                }
                .buttonStyle(SettingsSecondaryButtonStyle(tint: OffRecordColor.textCoral, fill: OffRecordColor.backgroundBlushTint))
                .accessibilityIdentifier("semanticMemory.delete")
                .disabled(semanticMemory.isBuilding || semanticMemory.chunkCount == 0)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("semanticMemory.section")
        }
    }

    @ViewBuilder
    private var systemSearchSection: some View {
        SettingsCard(
            title: "Siri & Search",
            systemImage: "magnifyingglass",
            tint: OffRecordColor.textSky,
            fill: OffRecordColor.surfacePrimary
        ) {
            Toggle("Show in Spotlight", isOn: $spotlightMetadataIndexingEnabled)
                .accessibilityIdentifier("settings.systemSearch.spotlightToggle")

            Text("Spotlight sees only dates, moods, and word counts, never your writing.")
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
                Label("Rebuild Spotlight Index", systemImage: "magnifyingglass")
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
            footer: "Reminders never include anything from your entries.",
            systemImage: "bell.badge",
            tint: OffRecordColor.textPeach,
            fill: OffRecordColor.surfacePeach
        ) {
            Toggle("Daily Reminder", isOn: Binding(
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
                    "Time",
                    selection: Binding(
                        get: { reminderManager.reminderTime },
                        set: { reminderManager.reminderTime = $0 }
                    ),
                    displayedComponents: .hourAndMinute
                )
            }

            Toggle("Smart Prompts from Friday", isOn: $reminderManager.usesFridaySmartPrompts)
                .accessibilityIdentifier("proactiveReflection.smartReminderToggle")
        }
    }

    private var weeklyReflectionSection: some View {
        SettingsCard(
            title: "Weekly Reflection",
            footer: "Notifications never include anything from your entries.",
            systemImage: "calendar.badge.clock",
            tint: OffRecordColor.textAqua,
            fill: OffRecordColor.surfaceMint
        ) {
            Toggle("Weekly Reflection", isOn: Binding(
                get: { weeklyReflection.settings.isEnabled },
                set: { value in weeklyReflection.updateSettings { $0.isEnabled = value } }
            ))
            .accessibilityIdentifier("weeklyReflection.settings.enabled")

            if weeklyReflection.settings.isEnabled {
                Picker("Day", selection: Binding(
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
                    "Time",
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

                Toggle("Show on Today", isOn: Binding(
                    get: { weeklyReflection.settings.showHomeCard },
                    set: { value in weeklyReflection.updateSettings { $0.showHomeCard = value } }
                ))

                Toggle("Notify Me", isOn: Binding(
                    get: { weeklyReflection.settings.sendNotification },
                    set: { value in handleWeeklyNotificationToggle(value) }
                ))
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
            footer: iCloudSyncEnabled ? "Recordings stay on this \(DeviceNoun.current) and don’t sync." : nil,
            systemImage: iCloudSyncEnabled && PersistenceController.isCloudAvailable ? "icloud.fill" : "icloud.slash",
            tint: iCloudSyncEnabled && PersistenceController.isCloudAvailable ? OffRecordColor.textSky : OffRecordColor.textTertiary,
            fill: OffRecordColor.surfaceBlue
        ) {
            Toggle(isOn: $iCloudSyncEnabled) {
                Text("iCloud Sync")
            }
            .onChange(of: iCloudSyncEnabled) { _, newValue in
                PersistenceController.shared.setCloudSyncEnabled(newValue)
                showCloudSyncRestartAlert = true
            }

            if iCloudSyncEnabled && !PersistenceController.isCloudAvailable {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(OffRecordColor.textPeach)
                        .font(OffRecordTypography.metadata)
                        .accessibilityHidden(true)
                    Text("Sign in to iCloud in Settings to sync.")
                        .font(OffRecordTypography.metadata)
                        .foregroundColor(OffRecordColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var syncStatusText: String {
        if !iCloudSyncEnabled {
            return "Off"
        }
        if PersistenceController.isCloudAvailable {
            return "On"
        }
        return "Not Signed In"
    }

    @ViewBuilder
    private var privacySection: some View {
        SettingsCard(
            title: "Privacy Policy",
            systemImage: "hand.raised.fill",
            tint: OffRecordColor.textSage,
            fill: OffRecordColor.surfaceSage
        ) {
            Text("OffRecord collects no data.")
                .font(OffRecordTypography.bodySmall)
                .foregroundColor(OffRecordColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

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
            footer: "Encrypted backups can’t be opened without their password.",
            systemImage: "archivebox",
            tint: OffRecordColor.textSky,
            fill: OffRecordColor.surfacePrimary
        ) {
            NavigationLink {
                BackupExportView(entries: startedEntries)
            } label: {
                SettingsActionRow(
                    systemImage: "square.and.arrow.up",
                    title: "Export",
                    subtitle: "Backup, text, Markdown, CSV",
                    tint: OffRecordColor.textSky
                )
            }

            NavigationLink {
                ImportBackupView()
            } label: {
                SettingsActionRow(
                    systemImage: "square.and.arrow.down",
                    title: "Restore from Backup",
                    tint: OffRecordColor.textSky
                )
            }
        }
    }

    @ViewBuilder
    private var storageSection: some View {
        SettingsCard(
            title: "Storage",
            systemImage: "internaldrive",
            tint: OffRecordColor.textAqua,
            fill: OffRecordColor.surfacePrimary
        ) {
            if isCalculatingStorage {
                SettingsRow(systemImage: "hourglass", title: "Calculating…", tint: OffRecordColor.textAqua) {
                    ProgressView()
                }
            } else {
                let total = audioStorageBytes + photoStorageBytes + databaseStorageBytes
                StorageRow(label: "Recordings", bytes: audioStorageBytes, totalBytes: total, icon: "waveform", color: OffRecordColor.textAqua)
                StorageRow(label: "Photos", bytes: photoStorageBytes, totalBytes: total, icon: "photo", color: OffRecordColor.textBlush)
                StorageRow(label: "Entries", bytes: databaseStorageBytes, totalBytes: total, icon: "cylinder", color: OffRecordColor.textPeach)

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
                Label("Refresh", systemImage: "arrow.clockwise")
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
            systemImage: "info.circle",
            tint: OffRecordColor.textBrand,
            fill: OffRecordColor.surfacePrimary
        ) {
            SettingsRow(systemImage: "number", title: "Version", tint: OffRecordColor.textBrand) {
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    .font(OffRecordTypography.bodySmall)
                    .foregroundColor(OffRecordColor.textPrimary)
            }

            SettingsRow(systemImage: "book.pages", title: "Entries", tint: OffRecordColor.textBrand) {
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
                settingsLogger.error("PDF export failed: \(error.localizedDescription, privacy: .public)")
                await MainActor.run {
                    exportError = "Try again."
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
