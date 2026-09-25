//
//  TodayView.swift
//  OffRecord
//
//  The daily ritual: a daypart hero with one prompt and one action, today's
//  entry, a single contextual card, nudges, and gentle progress. Voice capture
//  itself lives in the app-wide capture accessory (CaptureController).
//

import SwiftUI
import CoreData
import AppIntents

// MARK: - Today View

struct TodayView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("authorName") private var authorName: String = ""
    @ObservedObject private var proactiveReflection = ProactiveReflectionController.shared
    @ObservedObject private var weeklyReflection = WeeklyReflectionController.shared
    @ObservedObject private var navigationRouter = OffRecordNavigationRouter.shared
    @ObservedObject private var capture = CaptureController.shared

    @State private var noteEntry: DiaryEntry?
    @State private var isShowingNoteEditor = false
    @State private var shouldDeleteEmptyNoteDraft = false
    @State private var notePromptContext: String?
    @State private var noteHeroPromptID: String?
    @State private var selectedHero: SelectedDaypartHero?
    @State private var heroStore = DaypartHeroStore()
    @State private var lastExposedHeroPromptID: String?
    @State private var historicalEntries: [DiaryEntry] = []
    @State private var todayActivity: NSUserActivity?
    @State private var todayStats: JournalStatsSnapshot = .empty
    @State private var isShowingPrivacyExplanation = false
    @State private var showRecordSiriTip = true

    @FetchRequest private var todayEntries: FetchedResults<DiaryEntry>

    init() {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        _todayEntries = FetchRequest<DiaryEntry>(
            sortDescriptors: [NSSortDescriptor(keyPath: \DiaryEntry.date, ascending: false)],
            predicate: NSPredicate(format: "date >= %@ AND date < %@", startOfDay as NSDate, endOfDay as NSDate),
            animation: .default
        )
    }

    // MARK: Derived state

    private var latestEntry: DiaryEntry? {
        todayEntries.first(where: \.isStartedEntry)
    }

    private var todayEntriesSignature: String {
        todayEntries.map { entry in
            let updated = entry.updatedAt?.timeIntervalSinceReferenceDate ?? 0
            return "\(entry.objectID.uriRepresentation().absoluteString):\(updated)"
        }
        .joined(separator: "|")
    }

    private var effectiveLatestEntry: DiaryEntry? {
        if isHeroUITestEmptyToday || isHeroUITestFirstRun {
            return nil
        }
        return latestEntry
    }

    private var isHeroUITestEmptyToday: Bool {
        ProcessInfo.processInfo.arguments.contains("-HeroNudgeEmptyToday")
    }

    private var isHeroUITestFirstRun: Bool {
        ProcessInfo.processInfo.arguments.contains("-HeroNudgeFirstRun")
    }

    private var isFirstRun: Bool {
        isHeroUITestFirstRun || (historicalEntries.isEmpty && todayStats.isEmpty && effectiveLatestEntry == nil)
    }

    private var currentHero: SelectedDaypartHero? {
        let useCase: HeroUseCase = effectiveLatestEntry == nil ? .noEntryYet : .hasEntryAlready
        if let selectedHero,
           selectedHero.dayPart == DayPart.current(),
           selectedHero.prompt.useCase == useCase {
            return selectedHero
        }
        return DaypartHeroLibrary.selectHero(
            dayPart: DayPart.current(),
            hasEntryToday: effectiveLatestEntry != nil,
            store: heroStore
        )
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let baseGreeting: String
        switch hour {
        case 5..<12: baseGreeting = "Good morning"
        case 12..<17: baseGreeting = "Good afternoon"
        case 17..<21: baseGreeting = "Good evening"
        default: baseGreeting = "Good night"
        }
        return Personalization.appendFirstName(to: baseGreeting, name: authorName)
    }

    /// Past entries written on this calendar day in earlier years.
    private var onThisDayEntries: [DiaryEntry] {
        let calendar = Calendar.current
        let today = calendar.dateComponents([.month, .day, .year], from: Date())
        return historicalEntries.filter { entry in
            guard let date = entry.date else { return false }
            let parts = calendar.dateComponents([.month, .day, .year], from: date)
            return parts.month == today.month && parts.day == today.day && (parts.year ?? 0) < (today.year ?? 0)
        }
    }

    private enum ContextualCard {
        case weeklyReflection
        case proactivePrompt
        case onThisDay
    }

    /// One contextual card at a time, in priority order.
    private var contextualCard: ContextualCard? {
        if weeklyReflection.settings.isEnabled,
           weeklyReflection.settings.showHomeCard,
           weeklyReflection.currentReport?.isVisibleOnHome == true {
            return .weeklyReflection
        }
        if effectiveLatestEntry == nil, proactiveReflection.selectedPrompt?.priority == .high {
            return .proactivePrompt
        }
        if !onThisDayEntries.isEmpty {
            return .onThisDay
        }
        return nil
    }

    // MARK: Body

    var body: some View {
        GeometryReader { proxy in
            let metrics = OffRecordAdaptiveMetrics(
                width: proxy.size.width,
                horizontalSizeClass: horizontalSizeClass
            )

            ScrollView {
                VStack(spacing: 0) {
                    heroSection(topInset: proxy.safeAreaInsets.top, metrics: metrics)

                    VStack(spacing: OffRecordSpacing.xxl) {
                        if isFirstRun {
                            TodayFirstEntryCard(
                                onSpeak: { capture.startRecording(prompt: currentHero?.prompt.prompt) },
                                onWrite: { startTypedNote(promptContext: currentHero?.prompt.prompt, heroPromptID: currentHero?.prompt.id) }
                            )
                        }

                        contextualCardView

                        TodayNudgeSection(
                            prompts: EntryPrompt.defaultPrompts,
                            onWrite: { prompt in startTypedNote(promptContext: prompt.detail, heroPromptID: nil) },
                            onSpeak: { prompt in capture.startRecording(prompt: prompt.detail) }
                        )

                        if !isFirstRun {
                            TodayProgressStrip(stats: todayStats, hasEntryToday: effectiveLatestEntry != nil)
                        }

                        if metrics.mode.supportsSupplementaryPanels {
                            SiriTipView(intent: RecordJournalIntent(), isVisible: $showRecordSiriTip)
                                .siriTipViewStyle(.automatic)
                        }
                    }
                    .padding(.horizontal, metrics.pageHorizontalPadding)
                    .padding(.top, OffRecordSpacing.xxl)
                    .padding(.bottom, OffRecordSpacing.section)
                    .frame(maxWidth: metrics.readableContentMaxWidth ?? .infinity)
                    .frame(maxWidth: .infinity)
                }
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)
            .background(OffRecordAppBackground().ignoresSafeArea())
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $isShowingPrivacyExplanation) {
            HomePrivacyExplanationView()
                .presentationDetents([.medium, .large])
        }
        .navigationDestination(isPresented: $isShowingNoteEditor) {
            if let noteEntry {
                EntryDetailView(
                    entry: noteEntry,
                    startEditing: true,
                    deleteEmptyDraftOnDisappear: shouldDeleteEmptyNoteDraft,
                    promptContext: notePromptContext,
                    heroPromptID: noteHeroPromptID
                )
            }
        }
        .onAppear {
            refreshHero(recordExposure: false)
            startTodayPredictionActivity()
            consumePendingTypedNote()
        }
        .onDisappear {
            todayActivity?.resignCurrent()
            todayActivity = nil
        }
        .onChange(of: navigationRouter.pendingTypedNote) { _, _ in
            consumePendingTypedNote()
        }
        .onChange(of: latestEntry?.objectID) { _, _ in
            refreshHero(recordExposure: false)
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                historicalEntries = []
            case .active:
                Task { await refreshHistoricalEntryCache(recordHeroExposure: false) }
            default:
                break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .offRecordWillReleaseTransientMemory)) { _ in
            historicalEntries = []
        }
        .task(id: todayEntriesSignature) {
            await refreshHistoricalEntryCache(recordHeroExposure: true)
        }
        .background(todayKeyboardShortcuts)
    }

    private var todayKeyboardShortcuts: some View {
        Button("New journal note") {
            guard !capture.phase.isCapturing else { return }
            startTypedNote(promptContext: nil, heroPromptID: nil)
        }
        .keyboardShortcut("n", modifiers: .command)
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    // MARK: Hero

    @ViewBuilder
    private func heroSection(topInset: CGFloat, metrics: OffRecordAdaptiveMetrics) -> some View {
        if let hero = currentHero {
            TodayFullBleedHeroView(
                hero: hero,
                greeting: greeting,
                date: Date(),
                entriesThisYear: todayStats.entriesThisYear,
                todayEntry: effectiveLatestEntry,
                topSafeAreaInset: topInset,
                horizontalPadding: metrics.pageHorizontalPadding,
                onSpeak: {
                    capture.startRecording(prompt: hero.prompt.prompt)
                },
                onWrite: {
                    selectedHero = hero
                    startTypedNote(promptContext: hero.prompt.prompt, heroPromptID: hero.prompt.id)
                },
                onAnotherPrompt: { skipHero(hero) },
                onPrivacy: { isShowingPrivacyExplanation = true }
            )
        }
    }

    // MARK: Contextual card

    @ViewBuilder
    private var contextualCardView: some View {
        switch contextualCard {
        case .weeklyReflection:
            WeeklyReflectionHomeCard(entries: historicalEntries) {
                startTypedNote(promptContext: nil, heroPromptID: nil)
            }
            .transition(.opacity)
        case .proactivePrompt:
            ProactiveReflectionPromptCard(
                entries: historicalEntries,
                hasEntryToday: effectiveLatestEntry != nil
            ) { insight in
                startTypedNote(promptContext: insight.prompt, heroPromptID: nil)
            }
            .transition(.opacity)
        case .onThisDay:
            OnThisDayCard(entries: onThisDayEntries)
                .transition(.opacity)
        case nil:
            // Keeps the weekly reflection eligibility refresh running even when no card is shown.
            WeeklyReflectionHomeCard(entries: historicalEntries)
                .frame(height: 0)
                .hidden()
        }
    }

    // MARK: Actions

    private func consumePendingTypedNote() {
        guard let request = navigationRouter.pendingTypedNote else { return }
        navigationRouter.pendingTypedNote = nil
        startTypedNote(promptContext: request.promptContext, heroPromptID: nil)
    }

    private func startTypedNote(promptContext: String?, heroPromptID: String?) {
        guard !capture.phase.isCapturing else {
            capture.isPanelPresented = true
            return
        }
        let capturedAt = capture.captureTimestamp()
        let hadEntry = (try? DiaryEntryDailyStore.entries(on: capturedAt, in: viewContext).first)?.isStartedEntry == true
        guard let entry = capture.getOrCreateEntry(capturedAt: capturedAt) else {
            capture.alert = .entryCreationFailed
            return
        }
        noteEntry = entry
        notePromptContext = promptContext
        noteHeroPromptID = heroPromptID
        shouldDeleteEmptyNoteDraft = !hadEntry && !entry.isStartedEntry
        isShowingNoteEditor = true
        HapticManager.shared.selectionChanged()
    }

    private func skipHero(_ hero: SelectedDaypartHero) {
        heroStore.recordSkip(promptID: hero.prompt.id)
        withOffRecordAnimation(OffRecordMotion.gentle) {
            selectedHero = DaypartHeroLibrary.selectHero(
                dayPart: DayPart.current(),
                hasEntryToday: effectiveLatestEntry != nil,
                store: heroStore
            )
        }
        if let selectedHero {
            heroStore.recordExposure(selectedHero)
            lastExposedHeroPromptID = selectedHero.prompt.id
        }
        HapticManager.shared.selectionChanged()
    }

    private func refreshHero(recordExposure: Bool) {
        selectedHero = DaypartHeroLibrary.selectHero(
            dayPart: DayPart.current(),
            hasEntryToday: effectiveLatestEntry != nil,
            store: heroStore
        )
        if recordExposure, let selectedHero, lastExposedHeroPromptID != selectedHero.prompt.id {
            heroStore.recordExposure(selectedHero)
            lastExposedHeroPromptID = selectedHero.prompt.id
        }
    }

    private func startTodayPredictionActivity() {
        todayActivity?.resignCurrent()
        todayActivity = JournalSpotlightIndexer.shared.predictionActivity(
            type: "com.singularity.offrecord.today",
            title: "Write in OffRecord",
            route: .today
        )
        todayActivity?.becomeCurrent()
    }

    @MainActor
    private func refreshHistoricalEntryCache(recordHeroExposure: Bool) async {
        let token = PerformanceSignposts.begin("TodayHistoricalRefresh")
        defer { PerformanceSignposts.end(token) }

        let request: NSFetchRequest<DiaryEntry> = DiaryEntry.fetchRequest()
        request.predicate = DiaryEntry.startedEntryPredicate
        request.sortDescriptors = [NSSortDescriptor(keyPath: \DiaryEntry.date, ascending: false)]
        request.fetchBatchSize = 50

        do {
            let entries = try viewContext.fetch(request).startedEntries
            let stats = await JournalAnalyticsWorker.shared.makeStats(
                from: entries.journalSnapshots,
                now: Date(),
                weeklyTarget: GoalManager.shared.weeklyTarget,
                goalEnabled: false
            )
            historicalEntries = entries
            todayStats = stats
            proactiveReflection.refreshIfNeeded(entries: entries)
            refreshHero(recordExposure: recordHeroExposure)
        } catch {
            historicalEntries = []
            todayStats = .empty
        }
    }
}

// MARK: - First entry

/// Shown until the first entry exists: an invitation, not an empty list.
private struct TodayFirstEntryCard: View {
    let onSpeak: () -> Void
    let onWrite: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: OffRecordSpacing.lg) {
            HStack(alignment: .top, spacing: OffRecordSpacing.md) {
                FridayMascotView(pose: .wave, size: 56)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: OffRecordSpacing.xs) {
                    Text("Your first entry starts here")
                        .font(OffRecordTypography.cardTitle)
                        .foregroundStyle(OffRecordColor.textHeading)
                    Text("Say a few sentences about today. It stays on this device, and Friday starts learning what matters to you.")
                        .font(OffRecordTypography.bodySmall)
                        .foregroundStyle(OffRecordColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: OffRecordSpacing.md) {
                Button(action: onSpeak) {
                    Label("Speak", systemImage: "mic.fill")
                        .frame(maxWidth: .infinity)
                        .offRecordPillButton()
                }
                .buttonStyle(.plain)
                Button(action: onWrite) {
                    Label("Write", systemImage: "square.and.pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(OffRecordSoftButtonStyle())
            }
        }
        .padding(OffRecordSpacing.xl)
        .offRecordCard(fill: OffRecordColor.surfaceBlush, border: OffRecordColor.borderSoft)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.firstEntry")
    }
}

// MARK: - On This Day

struct OnThisDayCard: View {
    let entries: [DiaryEntry]

    private var entry: DiaryEntry? { entries.first }

    var body: some View {
        if let entry {
            NavigationLink {
                EntryDetailView(entry: entry)
            } label: {
                HStack(alignment: .top, spacing: OffRecordSpacing.md) {
                    moodArt(for: entry)
                    VStack(alignment: .leading, spacing: OffRecordSpacing.xs) {
                        Text(yearsAgoText(for: entry).uppercased())
                            .font(OffRecordTypography.labelSmall)
                            .foregroundStyle(OffRecordColor.textSky)
                            .tracking(0.6)
                        Text("On this day")
                            .font(OffRecordTypography.cardTitle)
                            .foregroundStyle(OffRecordColor.textHeading)
                        Text(snippet(for: entry))
                            .font(OffRecordTypography.bodySmall)
                            .foregroundStyle(OffRecordColor.textSecondary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                        if entries.count > 1 {
                            Text("+\(entries.count - 1) more from this date")
                                .font(OffRecordTypography.metadata)
                                .foregroundStyle(OffRecordColor.textTertiary)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(OffRecordTypography.labelMedium)
                        .foregroundStyle(OffRecordColor.textTertiary)
                        .accessibilityHidden(true)
                }
                .padding(OffRecordSpacing.xl)
                .offRecordCard(fill: OffRecordColor.surfaceBlue)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens the entry from \(yearsAgoText(for: entry)).")
            .accessibilityIdentifier("today.onThisDay")
        }
    }

    @ViewBuilder
    private func moodArt(for entry: DiaryEntry) -> some View {
        let mood = Mood(rawValue: entry.mood ?? "") ?? .none
        Group {
            if mood != .none {
                mood.miniImage
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "clock.arrow.circlepath")
                    .font(OffRecordTypography.titleSmall)
                    .foregroundStyle(OffRecordColor.textSky)
            }
        }
        .frame(width: 48, height: 48)
        .background(OffRecordColor.surfacePrimary.opacity(0.7), in: Circle())
        .accessibilityHidden(true)
    }

    private func yearsAgoText(for entry: DiaryEntry) -> String {
        let years = Calendar.current.dateComponents([.year], from: entry.date ?? Date(), to: Date()).year ?? 1
        return years <= 1 ? "1 year ago" : "\(years) years ago"
    }

    private func snippet(for entry: DiaryEntry) -> String {
        let text = entry.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !text.isEmpty { return text }
        if entry.hasStartedEntryAudio { return "A voice note you recorded." }
        return "A moment you saved."
    }
}

// MARK: - Progress strip

/// Gentle, self-referential progress: no loss framing, a warm welcome back after gaps.
struct TodayProgressStrip: View {
    let stats: JournalStatsSnapshot
    let hasEntryToday: Bool

    private var daysThisWeek: Int {
        stats.last7Days.filter { $0.hasEntry }.count
    }

    private var headline: String {
        if stats.currentStreak >= 2 {
            return "\(stats.currentStreak)-day rhythm"
        }
        if stats.entryCount > 0 && !hasEntryToday && stats.currentStreak == 0 {
            return "Welcome back"
        }
        return "\(daysThisWeek) of 7 days this week"
    }

    private var subtitle: String {
        if stats.currentStreak >= 2 {
            return hasEntryToday ? "Today's entry keeps it going." : "A few words today keeps it going."
        }
        if stats.entryCount > 0 && !hasEntryToday && stats.currentStreak == 0 {
            return "No catching up needed — just start with today."
        }
        return "\(stats.entriesThisYear) \(stats.entriesThisYear == 1 ? "entry" : "entries") this year"
    }

    var body: some View {
        HStack(spacing: OffRecordSpacing.md) {
            let isActive = stats.currentStreak >= 2 || hasEntryToday
            StreakFireArtworkView(
                imageName: isActive ? "StreakFire" : "StreakFireInactive",
                size: 44,
                accentFill: isActive ? OffRecordColor.brandPeach : OffRecordColor.brandLavender,
                isActive: isActive
            )
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .font(OffRecordTypography.labelLarge)
                    .foregroundStyle(OffRecordColor.textHeading)
                    .contentTransition(.numericText())
                Text(subtitle)
                    .font(OffRecordTypography.metadata)
                    .foregroundStyle(OffRecordColor.textSecondary)
            }
            Spacer(minLength: 0)
            WeekDots(days: stats.last7Days)
        }
        .padding(OffRecordSpacing.lg)
        .offRecordCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfacePeach, border: OffRecordColor.borderWarm, shadow: false)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("today.progress")
    }
}

private struct WeekDots: View {
    let days: [JournalDayActivity]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(days.suffix(7).enumerated()), id: \.offset) { _, day in
                Circle()
                    .fill(day.hasEntry ? OffRecordColor.textPeach : OffRecordColor.textTertiary.opacity(0.25))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Prompts

struct EntryPrompt: Identifiable, Equatable {
    enum Kind: Equatable {
        case dailyReflection
        case gratitude
        case energyCheck
        case lettingGo
        case selfKindness
        case tomorrow
        case custom
    }

    let id = UUID()
    let kind: Kind
    let title: String
    let detail: String

    static let defaultPrompts: [EntryPrompt] = [
        EntryPrompt(
            kind: .dailyReflection,
            title: "Daily reflection",
            detail: "What is one moment from today that you want to remember?"
        ),
        EntryPrompt(
            kind: .gratitude,
            title: "Gratitude",
            detail: "What are three small things you feel grateful for right now?"
        ),
        EntryPrompt(
            kind: .energyCheck,
            title: "Energy check",
            detail: "How does your body feel today - tense, tired, or calm?"
        ),
        EntryPrompt(
            kind: .lettingGo,
            title: "Letting go",
            detail: "What is one worry you can gently put down for tonight?"
        ),
        EntryPrompt(
            kind: .selfKindness,
            title: "Self-kindness",
            detail: "If you spoke to yourself like a friend, what would you say?"
        ),
        EntryPrompt(
            kind: .tomorrow,
            title: "Tomorrow",
            detail: "What is one gentle intention you have for tomorrow?"
        )
    ]
}
