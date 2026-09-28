//
//  TimelineView.swift
//  OffRecord
//
//  Displays all diary entries in a chronological timeline.
//  Supports search, filtering by starred entries, mood, date range, and delete.
//

import SwiftUI
import CoreData
#if os(iOS)
import Speech
import UIKit
#endif

/// Displays all diary entries grouped by month.
/// Supports search, starred filter, mood filter, date range, and pull-to-refresh.
struct TimelineView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ObservedObject private var semanticMemory = SemanticMemoryIndexController.shared
    @ObservedObject private var navigationRouter = OffRecordNavigationRouter.shared

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \DiaryEntry.date, ascending: false)],
        predicate: DiaryEntry.startedEntryPredicate,
        animation: .default)
    private var entries: FetchedResults<DiaryEntry>

    // MARK: - Search State

    @State private var searchText: String = ""
    @State private var showStarredOnly: Bool = false
    @State private var showFilters: Bool = false
    @State private var selectedMoodFilter: Mood? = nil
    @State private var startDate: Date? = nil
    @State private var endDate: Date? = nil
    @State private var isListening: Bool = false
    @State private var searchSuggestions: [FridayAssistantEngine.SearchSuggestion] = []
    @State private var semanticResults: [UUID: EvidenceReference] = [:]
    @State private var semanticSearchQuery: String = ""
    @State private var semanticSearchTask: Task<Void, Never>?
    @State private var isSemanticSearching = false
    @State private var semanticSearchMessage: String?
    @State private var semanticSearchAvailable = false
    @State private var isSearchFocused = false
    @State private var planterShakeTrigger = 0
    @State private var planterShakeAngle = 0.0
    @State private var filteredEntriesCache: [DiaryEntry] = []
    @State private var groupedEntriesCache: [SectionKey: [DiaryEntry]] = [:]
    @State private var sectionKeysCache: [SectionKey] = []
    @State private var summaryEntriesCache: [DiaryEntry] = []
    @State private var entryMetricsCache: [NSManagedObjectID: TimelineEntryPresentation] = [:]
    @State private var cachedEntriesSignature = ""
    @State private var routedEntry: DiaryEntry?
    @State private var selectedEntry: DiaryEntry?
    @State private var currentSearchActivity: NSUserActivity?
    @State private var showSpeechConsentPrompt = false
    @State private var lens: TimelineLens = .list
    @State private var navigatedEntry: DiaryEntry?
    @State private var pendingDeletion: PendingTimelineDeletion?
    @State private var bestMatchIDs: [UUID] = []
    @Namespace private var entryTransition

    #if os(iOS)
    @StateObject private var voiceSearch = VoiceSearchManager()
    #endif

    private var assistant: FridayAssistantEngine { FridayAssistantEngine.shared }
    private var entriesSignature: String {
        entries.map { entry in
            let updated = entry.updatedAt?.timeIntervalSinceReferenceDate ?? 0
            return "\(entry.objectID.uriRepresentation().absoluteString):\(updated)"
        }
        .joined(separator: "|")
    }
    private var cacheSignature: String {
        [
            entriesSignature,
            searchText,
            showStarredOnly.description,
            selectedMoodFilter?.rawValue ?? "",
            String(startDate?.timeIntervalSinceReferenceDate ?? 0),
            String(endDate?.timeIntervalSinceReferenceDate ?? 0),
            semanticSearchQuery,
            isSemanticSearching.description,
            semanticSearchAvailable.description,
            effectiveSemanticResults.keys.map(\.uuidString).sorted().joined(separator: ","),
            pendingDeletion?.objectID.uriRepresentation().absoluteString ?? ""
        ].joined(separator: "|")
    }

    private var effectiveSemanticResults: [UUID: EvidenceReference] {
        semanticSearchAvailable ? semanticResults : [:]
    }

    var body: some View {
        GeometryReader { proxy in
            let metrics = OffRecordAdaptiveMetrics(
                width: proxy.size.width,
                horizontalSizeClass: horizontalSizeClass
            )

            if metrics.mode.supportsSupplementaryPanels {
                timelineSplit(metrics: metrics)
            } else {
                timelineList(
                    maxWidth: TimelineDesign.maxContentWidth,
                    selectedEntryID: nil,
                    onSelect: nil
                )
            }
        }
        .background {
            OffRecordAppBackground()
                .ignoresSafeArea()
        }
        .navigationTitle("Timeline")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(item: $navigatedEntry) { entry in
            EntryDetailView(entry: entry)
                .navigationTransition(.zoom(sourceID: entry.objectID, in: entryTransition))
        }
        .navigationDestination(isPresented: Binding(
            get: { routedEntry != nil },
            set: { isPresented in
                if !isPresented {
                    navigationRouter.clearEntryRouteIfNeeded(routedEntry?.id)
                    routedEntry = nil
                }
            }
        )) {
            if let routedEntry {
                EntryDetailView(entry: routedEntry)
            }
        }
        .overlay(alignment: .bottom) {
            if let pendingDeletion {
                TimelineUndoToast(
                    message: String(localized: "Entry deleted"),
                    onUndo: undoPendingDeletion
                )
                .padding(.horizontal, OffRecordSpacing.screenX)
                .padding(.bottom, OffRecordSpacing.md)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .id(pendingDeletion.id)
            }
        }
        .offRecordAnimation(OffRecordMotion.snappy, value: pendingDeletion?.id)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                starredToolbarButton
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                toolbarActions
            }
        }
        .alert(SpeechTranscriptionConsent.disclosureTitle, isPresented: $showSpeechConsentPrompt) {
            Button("Continue") {
                SpeechTranscriptionConsent.grantAppleSpeechProcessing()
                startVoiceSearch()
            }
        } message: {
            Text(SpeechTranscriptionConsent.disclosureMessage)
        }
        #if os(iOS)
        .onChange(of: voiceSearch.transcribedText) { _, newValue in
            if !newValue.isEmpty {
                searchText = newValue
            }
        }
        .onChange(of: voiceSearch.isListening) { _, listening in
            isListening = listening
        }
        .onChange(of: voiceSearch.errorMessage) { _, error in
            if error != nil {
                isListening = false
            }
        }
        #endif
        .onChange(of: searchText) { _, newValue in
            handleSearchTextChanged(newValue)
            updateSearchActivity(for: newValue)
        }
        .onChange(of: navigationRouter.timelineSearchText) { _, newValue in
            applyRoutedSearch(newValue)
        }
        .onChange(of: navigationRouter.routedEntryID) { _, newValue in
            resolveRoutedEntry(newValue)
        }
        .onChange(of: semanticMemory.isBuilding) { _, isBuilding in
            guard !isBuilding else { return }
            let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count >= 2, isSemanticSearching {
                scheduleSemanticSearch(trimmed)
            }
        }
        .onAppear {
            semanticMemory.ensureIndexed(entries: entries.startedEntries)
            applyRoutedSearch(navigationRouter.timelineSearchText)
            resolveRoutedEntry(navigationRouter.routedEntryID)
        }
        .onDisappear {
            currentSearchActivity?.resignCurrent()
            currentSearchActivity = nil
            commitPendingDeletion()
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                clearTimelineCache()
            case .active:
                refreshTimelineCache()
            default:
                break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .offRecordWillReleaseTransientMemory)) { _ in
            clearTimelineCache()
        }
        .task(id: cacheSignature) {
            if cachedEntriesSignature != entriesSignature {
                normalizeDuplicateDaysIfNeeded()
                cachedEntriesSignature = entriesSignature
            }
            refreshTimelineCache()
        }
        .background(timelineKeyboardShortcuts)
    }

    private var timelineKeyboardShortcuts: some View {
        Button("Search") {
            isSearchFocused = true
        }
        .keyboardShortcut("f", modifiers: .command)
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    private func timelineList(
        maxWidth: CGFloat,
        selectedEntryID: UUID?,
        onSelect: ((DiaryEntry) -> Void)?
    ) -> some View {
        List {
            Group {
                VStack(alignment: .leading, spacing: TimelineDesign.contentSpacing) {
                    VStack(alignment: .leading, spacing: TimelineDesign.headerSearchSpacing) {
                        timelineHeader
                        searchArea
                    }
                    .overlay(alignment: .topTrailing) {
                        timelinePlanterArtwork
                    }

                    if showFilters {
                        filterBar
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    if hasActiveFilters {
                        activeFiltersBar
                            .transition(.opacity)
                    }

                    semanticSearchStatusBanner

                    #if os(iOS)
                    voiceSearchErrorBanner
                    #endif

                    if !entries.isEmpty {
                        lensPicker
                    }

                    if lens == .list, !filteredEntriesCache.isEmpty, !isSearching {
                        MonthSummaryCard(
                            title: summaryTitle,
                            entries: summaryEntriesCache
                        )
                    }
                }
                .timelineRowLayout(maxWidth: maxWidth, bottom: TimelineDesign.contentSpacing)

                switch lens {
                case .list:
                    listContent(maxWidth: maxWidth, selectedEntryID: selectedEntryID, onSelect: onSelect)
                case .calendar:
                    TimelineCalendarView(entries: visibleEntries) { entry in
                        open(entry, onSelect: onSelect)
                    }
                    .timelineRowLayout(maxWidth: maxWidth, bottom: OffRecordSpacing.section)
                case .media:
                    TimelineMediaGrid(entries: visibleEntries) { entry in
                        open(entry, onSelect: onSelect)
                    }
                    .timelineRowLayout(maxWidth: maxWidth, bottom: OffRecordSpacing.section)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
        .offRecordAnimation(OffRecordMotion.gentle, value: lens)
    }

    private var lensPicker: some View {
        Picker(selection: $lens) {
            ForEach(TimelineLens.allCases) { lens in
                Label(lens.displayName, systemImage: lens.systemImage).tag(lens)
            }
        } label: {
            Text("View", comment: "Accessibility label for the picker that switches the timeline between list, calendar, and photos.")
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("timeline.lensPicker")
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Entries not waiting on an undoable delete.
    private var visibleEntries: [DiaryEntry] {
        entries.startedEntries.filter { $0.objectID != pendingDeletion?.objectID }
    }

    private var summaryTitle: String {
        guard let date = summaryEntriesCache.first?.date else { return String(localized: "This Month") }
        if Calendar.current.isDate(date, equalTo: Date(), toGranularity: .month) {
            return String(localized: "This Month")
        }
        return date.formatted(.dateTime.month(.wide).year())
    }

    @ViewBuilder
    private func listContent(
        maxWidth: CGFloat,
        selectedEntryID: UUID?,
        onSelect: ((DiaryEntry) -> Void)?
    ) -> some View {
        if entries.isEmpty {
            TimelineFirstEntryState()
                .timelineRowLayout(maxWidth: maxWidth, bottom: OffRecordSpacing.section)
        } else if filteredEntriesCache.isEmpty {
            emptySearchState
                .timelineRowLayout(maxWidth: maxWidth, bottom: OffRecordSpacing.section)
        } else {
            let bestMatches = bestMatchEntries
            if !bestMatches.isEmpty {
                Section {
                    ForEach(Array(bestMatches.enumerated()), id: \.element.objectID) { index, entry in
                        entryRow(entry, index: index, isLast: index == bestMatches.count - 1, maxWidth: maxWidth, selectedEntryID: selectedEntryID, onSelect: onSelect, transitionSuffix: "best")
                    }
                } header: {
                    TimelineSectionHeader(title: String(localized: "Top Results"), count: nil, systemImage: "sparkle.magnifyingglass")
                        .timelineHeaderLayout(maxWidth: maxWidth)
                }
            }

            ForEach(sectionKeysCache, id: \.self) { key in
                if let sectionEntries = groupedEntriesCache[key] {
                    Section {
                        ForEach(Array(sectionEntries.enumerated()), id: \.element.objectID) { index, entry in
                            entryRow(entry, index: index, isLast: index == sectionEntries.count - 1, maxWidth: maxWidth, selectedEntryID: selectedEntryID, onSelect: onSelect, transitionSuffix: nil)
                        }
                    } header: {
                        TimelineSectionHeader(
                            title: sectionTitle(for: key),
                            count: sectionEntries.count,
                            systemImage: nil
                        )
                        .timelineHeaderLayout(maxWidth: maxWidth)
                    }
                }
            }

            Color.clear
                .frame(height: OffRecordSpacing.section)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
    }

    private var bestMatchEntries: [DiaryEntry] {
        guard isSearching, !bestMatchIDs.isEmpty else { return [] }
        let byID = Dictionary(filteredEntriesCache.compactMap { entry in entry.id.map { ($0, entry) } }, uniquingKeysWith: { first, _ in first })
        return bestMatchIDs.compactMap { byID[$0] }
    }

    @ViewBuilder
    private func entryRow(
        _ entry: DiaryEntry,
        index: Int,
        isLast: Bool,
        maxWidth: CGFloat,
        selectedEntryID: UUID?,
        onSelect: ((DiaryEntry) -> Void)?,
        transitionSuffix: String?
    ) -> some View {
        TimelineDayRow(
            entry: entry,
            index: index,
            isLast: isLast,
            metrics: entryMetricsCache[entry.objectID],
            searchText: searchText,
            evidence: entry.id.flatMap { effectiveSemanticResults[$0] },
            isSelected: entry.id == selectedEntryID,
            onSelect: { open(entry, onSelect: onSelect) }
        )
        .matchedTransitionSource(id: transitionSuffix == nil ? AnyHashable(entry.objectID) : AnyHashable("\(transitionSuffix!)-\(entry.objectID)"), in: entryTransition)
        .timelineRowLayout(maxWidth: maxWidth, bottom: TimelineDesign.monthRowSpacing)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                requestDelete(entry)
            } label: {
                Label(String(localized: "Delete", comment: "Action that deletes an entry."), systemImage: "trash")
            }
            .tint(.red)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                toggleStar(entry)
            } label: {
                Label(entry.isStarred ? "Unstar" : "Star", systemImage: entry.isStarred ? "star.slash" : "star.fill")
            }
            .tint(OffRecordColor.textYellow)
        }
        .contextMenu {
            Button {
                open(entry, onSelect: onSelect)
            } label: {
                Label("Open", systemImage: "book.pages")
            }
            Button {
                toggleStar(entry)
            } label: {
                Label(entry.isStarred ? "Unstar" : "Star", systemImage: entry.isStarred ? "star.slash" : "star")
            }
            if let text = entry.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                Button {
                    UIPasteboard.general.string = TimelineEntryPreviewSanitizer.sanitize(text)
                } label: {
                    Label("Copy Text", systemImage: "doc.on.doc")
                }
            }
            Divider()
            Button(role: .destructive) {
                requestDelete(entry)
            } label: {
                Label(String(localized: "Delete", comment: "Action that deletes an entry."), systemImage: "trash")
            }
        } preview: {
            TimelineEntryContextPreview(entry: entry)
        }
    }

    private func open(_ entry: DiaryEntry, onSelect: ((DiaryEntry) -> Void)?) {
        commitPendingDeletion()
        if let onSelect {
            onSelect(entry)
        } else {
            navigatedEntry = entry
        }
    }

    private func timelineSplit(metrics: OffRecordAdaptiveMetrics) -> some View {
        HStack(spacing: 0) {
            timelineList(
                maxWidth: metrics.timelineListWidth,
                selectedEntryID: selectedEntry?.id,
                onSelect: { entry in
                    selectedEntry = entry
                    HapticManager.shared.selectionChanged()
                }
            )
            .frame(width: metrics.timelineListWidth)
            .background(OffRecordAppBackground())

            Divider()
                .overlay(OffRecordColor.borderSoft)

            Group {
                if let selectedEntry {
                    EntryDetailView(entry: selectedEntry, showsDismissButton: false)
                        .id(selectedEntry.objectID)
                } else {
                    timelineDetailPlaceholder
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var timelineDetailPlaceholder: some View {
        VStack(spacing: OffRecordSpacing.lg) {
            OffRecordIconBubble(
                systemImage: "book.pages",
                tint: OffRecordColor.textLavender,
                fill: OffRecordColor.surfaceLavender,
                size: 58,
                iconSize: 24
            )

            Text("No Entry Selected")
                .font(OffRecordTypography.titleMedium)
                .foregroundStyle(OffRecordColor.textHeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OffRecordColor.backgroundPrimary.opacity(0.82))
    }

    // MARK: - Header

    private var timelineHeader: some View {
        Color.clear
            .frame(
                height: dynamicTypeSize.isAccessibilitySize
                    ? TimelineDesign.accessibilityHeaderHeight
                    : TimelineDesign.compactHeaderHeight
            )
            .frame(maxWidth: .infinity)
    }

    private var timelinePlanterArtwork: some View {
        Button(action: triggerPlanterShake) {
            Image("CreeperPlant01")
                .resizable()
                .scaledToFit()
                .frame(width: TimelineDesign.planterWidth)
                .fixedSize()
                .rotationEffect(.degrees(planterShakeAngle), anchor: .top)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .offset(
            x: -16,
            y: dynamicTypeSize.isAccessibilitySize ? 28 : -66
        )
        .accessibilityHidden(true)
        .task(id: planterShakeTrigger) {
            await runPlanterShake()
        }
    }

    private func triggerPlanterShake() {
        HapticManager.shared.selectionChanged()

        if reduceMotion {
            planterShakeAngle = 0
        } else {
            planterShakeTrigger += 1
        }
    }

    @MainActor
    private func runPlanterShake() async {
        guard planterShakeTrigger > 0, !reduceMotion else {
            planterShakeAngle = 0
            return
        }

        for angle in [-2.0, 1.6, -0.8, 0.4, 0] {
            guard !Task.isCancelled else { return }

            withAnimation(.easeInOut(duration: 0.05)) {
                planterShakeAngle = angle
            }

            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private var starredToolbarButton: some View {
        Button {
            showStarredOnly.toggle()
            HapticManager.shared.selectionChanged()
        } label: {
            Image(systemName: showStarredOnly ? "star.fill" : "star")
                .foregroundStyle(showStarredOnly ? OffRecordColor.textYellow : OffRecordColor.textBrand)
                .contentTransition(.symbolEffect(.replace))
        }
        .accessibilityLabel(Text("Starred", comment: "Accessibility label for the toolbar button that shows only starred entries."))
        .accessibilityAddTraits(showStarredOnly ? .isSelected : [])
    }

    private var toolbarActions: some View {
        HStack(spacing: 12) {
            #if os(iOS)
            Button {
                toggleVoiceSearch()
            } label: {
                Image(systemName: isListening || voiceSearch.isPreparingModel ? "mic.fill" : "mic")
                    .foregroundStyle(isListening || voiceSearch.isPreparingModel ? OffRecordColor.textCoral : OffRecordColor.textBrand)
                    .symbolEffect(.pulse, isActive: isListening)
                    .contentTransition(.symbolEffect(.replace))
            }
            .accessibilityLabel("Voice Search")
            #endif

            Button {
                withOffRecordAnimation(OffRecordMotion.snappy) {
                    showFilters.toggle()
                }
                HapticManager.shared.buttonTap()
            } label: {
                Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    .foregroundStyle(OffRecordColor.textLavender)
                    .contentTransition(.symbolEffect(.replace))
            }
            .accessibilityLabel("Filters")
            .accessibilityValue(hasActiveFilters ? "On" : "")
        }
    }

    // MARK: - Search

    private var searchArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            TimelineSearchField(
                text: $searchText,
                isFocused: $isSearchFocused,
                onCancel: { dismissTimelineSearch(clearText: true) }
            )
                .frame(height: TimelineDesign.searchHeight)
                .accessibilityIdentifier("timeline.searchField")

            if !searchSuggestions.isEmpty {
                searchSuggestionStrip
            }
        }
    }

    private var searchSuggestionStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(searchSuggestions, id: \.text) { suggestion in
                    Button {
                        if suggestion.type == "mood", let mood = Mood(rawValue: suggestion.text.lowercased()) {
                            selectedMoodFilter = mood
                            searchText = ""
                        } else {
                            searchText = suggestion.text
                        }
                        HapticManager.shared.selectionChanged()
                    } label: {
                        Label(suggestion.text, systemImage: suggestion.icon)
                            .font(OffRecordTypography.labelSmall)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .foregroundStyle(OffRecordReadableTintStyle.privacy.foreground)
                            .background(OffRecordReadableTintStyle.privacy.fill, in: Capsule())
                            .overlay(Capsule().stroke(OffRecordReadableTintStyle.privacy.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Status

    @ViewBuilder
    private var semanticSearchStatusBanner: some View {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, semanticMemory.isBuilding {
            HStack(spacing: 10) {
                ProgressView(value: semanticMemory.progress)
                    .frame(width: 44)
                Text("Updating Search")
                    .font(OffRecordTypography.labelSmall)
                    .foregroundColor(OffRecordColor.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(OffRecordColor.surfaceWarm, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("semanticMemory.buildingTitle")
        } else if !trimmed.isEmpty, let semanticSearchMessage {
            Text(semanticSearchMessage)
                .font(OffRecordTypography.metadata)
                .foregroundColor(OffRecordColor.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(OffRecordColor.surfaceWarm, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .accessibilityIdentifier("semanticMemory.searchMessage")
        }
    }

    // MARK: - Voice Search Error

    #if os(iOS)
    @ViewBuilder
    private var voiceSearchErrorBanner: some View {
        if voiceSearch.isPreparingModel {
            HStack(spacing: 10) {
                if let progress = voiceSearch.modelDownloadProgress {
                    ProgressView(value: progress)
                        .frame(width: 52)
                } else {
                    ProgressView()
                }
                Text("Preparing voice search…")
                    .font(OffRecordTypography.labelSmall)
                    .foregroundStyle(OffRecordColor.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                OffRecordColor.surfaceWarm,
                in: RoundedRectangle(cornerRadius: OffRecordRadius.lg, style: .continuous)
            )
        } else if let error = voiceSearch.errorMessage {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(OffRecordColor.textCoral)
                    .font(OffRecordTypography.labelMedium)
                Text(error)
                    .font(OffRecordTypography.labelSmall)
                    .foregroundStyle(OffRecordColor.textSecondary)
                Spacer()
                Button {
                    voiceSearch.errorMessage = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(OffRecordTypography.annotation.weight(.bold))
                        .foregroundStyle(OffRecordColor.textTertiary)
                        .frame(width: OffRecordLayout.minimumTapTarget, height: OffRecordLayout.minimumTapTarget)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                OffRecordColor.surfacePeach,
                in: RoundedRectangle(cornerRadius: OffRecordRadius.lg, style: .continuous)
            )
            .transition(.opacity.combined(with: .move(edge: .top)))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("voiceSearch.errorBanner")
        }
    }
    #endif

    // MARK: - Filter Bar

    private var filterBar: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Text("Mood", comment: "Label before the row of mood filters.")
                        .font(OffRecordTypography.metadata)
                        .foregroundColor(OffRecordColor.textSecondary)

                    ForEach(Mood.allCases.filter { $0 != .none }, id: \.self) { mood in
                        Button {
                            withOffRecordAnimation(OffRecordMotion.snappy) {
                                selectedMoodFilter = selectedMoodFilter == mood ? nil : mood
                            }
                            HapticManager.shared.selectionChanged()
                        } label: {
                            HStack(spacing: 4) {
                                MiniMoodIcon(
                                    mood: mood,
                                    size: 14,
                                    opacity: selectedMoodFilter == mood ? 0.92 : 0.72
                                )
                                Text(mood.displayName)
                            }
                            .font(OffRecordTypography.metadata)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .foregroundColor(selectedMoodFilter == mood ? mood.readableStyle.foreground : OffRecordColor.textSecondary)
                            .offRecordGlassControl(
                                tint: selectedMoodFilter == mood ? mood.readableStyle.tint : nil,
                                in: Capsule(),
                                fallbackFill: selectedMoodFilter == mood ? mood.readableStyle.fill : OffRecordReadableTintStyle.neutral.fill,
                                border: selectedMoodFilter == mood ? mood.readableStyle.border : OffRecordReadableTintStyle.neutral.border
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 12) {
                DateRangeButton(title: String(localized: "From", comment: "Button that sets the start date of the date filter."), date: $startDate)
                DateRangeButton(title: String(localized: "To", comment: "Button that sets the end date of the date filter."), date: $endDate)

                Spacer()

                if startDate != nil || endDate != nil {
                    Button("Clear Dates") {
                        withOffRecordAnimation(OffRecordMotion.snappy) {
                            startDate = nil
                            endDate = nil
                        }
                        HapticManager.shared.buttonTap()
                    }
                    .font(OffRecordTypography.metadata)
                    .foregroundColor(OffRecordColor.textCoral)
                }
            }
        }
        .padding(14)
        .background(OffRecordColor.surfaceWarm.opacity(0.92), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(OffRecordColor.borderSoft, lineWidth: 1)
        )
    }

    // MARK: - Active Filters Bar

    private var activeFiltersBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if showStarredOnly {
                    FilterChip(label: String(localized: "Starred", comment: "Active filter chip: showing only starred entries."), icon: "star.fill", style: .highlight) {
                        showStarredOnly = false
                    }
                }

                if let mood = selectedMoodFilter {
                    FilterChip(label: mood.displayName, mood: mood, style: mood.readableStyle) {
                        selectedMoodFilter = nil
                    }
                }

                if let start = startDate {
                    FilterChip(label: String(localized: "From \(formatShortDate(start))", comment: "Active filter chip. The argument is the start date."), icon: "calendar", style: .export) {
                        startDate = nil
                    }
                }

                if let end = endDate {
                    FilterChip(label: String(localized: "To \(formatShortDate(end))", comment: "Active filter chip. The argument is the end date."), icon: "calendar", style: .export) {
                        endDate = nil
                    }
                }

                if hasActiveFilters {
                    Button("Clear All") {
                        clearAllFilters()
                    }
                    .font(OffRecordTypography.labelSmall)
                    .foregroundColor(OffRecordColor.textCoral)
                    .padding(.leading, 8)
                }
            }
        }
    }

    private var emptySearchState: some View {
        VStack(spacing: 16) {
            Image(systemName: semanticMemory.isBuilding ? "brain.head.profile" : "magnifyingglass")
                .font(OffRecordTypography.titleLarge)
                .foregroundColor(OffRecordColor.textSecondary)
                .symbolEffect(.pulse, isActive: semanticMemory.isBuilding)
                .accessibilityHidden(true)

            Text(semanticMemory.isBuilding ? "Updating Search" : "No Results")
                .font(OffRecordTypography.sectionTitle)
                .foregroundColor(OffRecordColor.textHeading)
                .accessibilityIdentifier(semanticMemory.isBuilding ? "semanticMemory.buildingTitle" : "timeline.emptyTitle")

            if semanticMemory.isBuilding {
                ProgressView(value: semanticMemory.progress)
                    .frame(maxWidth: 220)
                Text("Results will improve when it’s done.")
                    .font(OffRecordTypography.metadata)
                    .foregroundColor(OffRecordColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .accessibilityIdentifier("semanticMemory.buildingMessage")
            } else if let semanticSearchMessage {
                Text(semanticSearchMessage)
                    .font(OffRecordTypography.metadata)
                    .foregroundColor(OffRecordColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .accessibilityIdentifier("semanticMemory.searchMessage")
            }

            if hasActiveFilters {
                Button("Clear Filters") {
                    clearAllFilters()
                }
                .font(OffRecordTypography.bodySmall)
                .foregroundColor(OffRecordColor.textBrand)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, OffRecordSpacing.section)
        .padding(.horizontal, OffRecordSpacing.xl)
        .background(OffRecordColor.surfacePrimary.opacity(0.72), in: RoundedRectangle(cornerRadius: OffRecordRadius.lg, style: .continuous))
    }

    // MARK: - Voice Search

    private func toggleVoiceSearch() {
        #if os(iOS)
        if isListening || voiceSearch.isPreparingModel {
            voiceSearch.stopListening()
            isListening = false
        } else {
            guard SpeechTranscriptionConsent.hasGrantedAppleSpeechProcessing else {
                showSpeechConsentPrompt = true
                return
            }
            startVoiceSearch()
        }
        #endif
    }

    private func startVoiceSearch() {
        #if os(iOS)
        voiceSearch.startListening()
        guard voiceSearch.errorMessage == nil else { return }
        HapticManager.shared.recordingStarted()
        #endif
    }

    // MARK: - Search Helpers

    private func handleSearchTextChanged(_ newValue: String) {
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count >= 2 {
            searchSuggestions = assistant.searchSuggestions(for: trimmed)
            scheduleSemanticSearch(trimmed)
        } else {
            searchSuggestions = []
            semanticResults = [:]
            bestMatchIDs = []
            semanticSearchQuery = ""
            semanticSearchAvailable = false
            semanticSearchTask?.cancel()
            isSemanticSearching = false
            semanticSearchMessage = nil
        }
    }

    private func applyRoutedSearch(_ newValue: String) {
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != searchText else { return }
        searchText = trimmed
        isSearchFocused = true
    }

    private func resolveRoutedEntry(_ id: UUID?) {
        guard let id else { return }
        if let entry = entries.startedEntries.first(where: { $0.id == id }) {
            routedEntry = entry
        } else {
            JournalSpotlightIndexer.shared.delete(entryID: id)
            navigationRouter.clearEntryRouteIfNeeded(id)
        }
    }

    private func updateSearchActivity(for query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        currentSearchActivity?.resignCurrent()
        currentSearchActivity = nil

        guard trimmed.count >= 2,
              let activity = JournalSpotlightIndexer.shared.predictionActivity(
                type: "com.singularity.offrecord.searchTimeline",
                title: String(localized: "Search OffRecord Timeline"),
                route: .timeline(query: trimmed)
              ) else {
            return
        }

        activity.becomeCurrent()
        currentSearchActivity = activity
    }

    private func dismissTimelineSearch(clearText: Bool) {
        if clearText {
            searchText = ""
        }
        isSearchFocused = false
        #if os(iOS)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }

    private func scheduleSemanticSearch(_ query: String) {
        semanticSearchTask?.cancel()
        let entrySnapshot = entries.startedEntries
        semanticSearchTask = Task {
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                isSemanticSearching = true
                semanticSearchQuery = query
                semanticSearchMessage = String(localized: "Searching…")
            }
            let searchResult = await semanticMemory.search(query: query, entries: entrySnapshot, limit: 48)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                switch searchResult {
                case .ready(let results):
                    var bestByEntry: [UUID: EvidenceReference] = [:]
                    for result in results {
                        if let existing = bestByEntry[result.entryID] {
                            if result.score > existing.score {
                                bestByEntry[result.entryID] = result
                            }
                        } else {
                            bestByEntry[result.entryID] = result
                        }
                    }
                    semanticResults = bestByEntry
                    bestMatchIDs = bestByEntry.values
                        .filter { $0.score >= 0.35 }
                        .sorted { $0.score > $1.score }
                        .prefix(3)
                        .map(\.entryID)
                    semanticSearchAvailable = !bestByEntry.isEmpty
                    semanticSearchMessage = nil
                    isSemanticSearching = false
                case .building(_, let message):
                    semanticSearchAvailable = false
                    semanticSearchMessage = message
                    isSemanticSearching = true
                case .unavailable(let message), .failed(let message):
                    semanticSearchAvailable = false
                    semanticSearchMessage = message
                    isSemanticSearching = false
                }
            }
        }
    }

    // MARK: - Filter Helpers

    private var hasActiveFilters: Bool {
        showStarredOnly || selectedMoodFilter != nil || startDate != nil || endDate != nil
    }

    private func clearAllFilters() {
        withOffRecordAnimation(OffRecordMotion.snappy) {
            showStarredOnly = false
            selectedMoodFilter = nil
            startDate = nil
            endDate = nil
            searchText = ""
            semanticResults = [:]
            semanticSearchQuery = ""
            semanticSearchAvailable = false
            semanticSearchMessage = nil
            bestMatchIDs = []
        }
        HapticManager.shared.buttonTap()
    }

    private func formatShortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter.string(from: date)
    }

    // MARK: - Grouping

    private struct SectionKey: Hashable {
        let year: Int
        let month: Int
    }

    @MainActor
    private func refreshTimelineCache() {
        let token = PerformanceSignposts.begin("TimelineFilterAndGroup")
        let pendingID = pendingDeletion?.objectID
        let filteredEntries = entries.startedEntries.filter { entry in
            guard !entry.isDeleted, entry.objectID != pendingID else { return false }
            guard let entryDate = entry.date else { return false }

            if showStarredOnly && !entry.isStarred { return false }

            if let moodFilter = selectedMoodFilter {
                let entryMood = entry.value(forKey: "mood") as? String ?? ""
                if entryMood != moodFilter.rawValue { return false }
            }

            if let start = startDate {
                let startOfDay = Calendar.current.startOfDay(for: start)
                if entryDate < startOfDay { return false }
            }
            if let end = endDate {
                let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: end)) ?? end
                if entryDate >= endOfDay { return false }
            }

            let searchTrimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !searchTrimmed.isEmpty {
                if semanticSearchQuery == searchTrimmed, !isSemanticSearching, semanticSearchAvailable, !semanticResults.isEmpty {
                    guard let id = entry.id else { return false }
                    if semanticResults[id] == nil { return false }
                } else {
                    let text = entry.text ?? ""
                    if !text.localizedCaseInsensitiveContains(searchTrimmed) { return false }
                }
            }

            return true
        }

        let calendar = Calendar.current
        let groups = Dictionary(grouping: filteredEntries) { (entry: DiaryEntry) -> SectionKey in
            let date = entry.date ?? Date.distantPast
            let comps = calendar.dateComponents([.year, .month], from: date)
            return SectionKey(year: comps.year ?? 0, month: comps.month ?? 0)
        }
        let groupedEntries = groups.mapValues { entries in
            entries.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        }
        let sectionKeys = groupedEntries.keys.sorted { lhs, rhs in
            if lhs.year != rhs.year { return lhs.year > rhs.year }
            return lhs.month > rhs.month
        }
        let summaryEntries = sectionKeys.first.flatMap { groupedEntries[$0] } ?? []
        let metrics = Dictionary(uniqueKeysWithValues: filteredEntries.map { entry in
            (
                entry.objectID,
                TimelineEntryPresentation(
                    wordCount: TimelineEntryMetrics.wordCount(for: entry),
                    hasPhotos: (entry.photos?.count ?? 0) > 0
                )
            )
        })

        filteredEntriesCache = filteredEntries
        groupedEntriesCache = groupedEntries
        sectionKeysCache = sectionKeys
        summaryEntriesCache = summaryEntries
        entryMetricsCache = metrics
        PerformanceSignposts.end(token)
    }

    @MainActor
    private func normalizeDuplicateDaysIfNeeded() {
        do {
            let normalizedEntries = try DiaryEntryDailyStore.normalizeAllDuplicateDays(in: viewContext)
            guard viewContext.hasChanges else { return }
            try viewContext.save()
            viewContext.processPendingChanges()
            for entry in normalizedEntries where !entry.isDeleted {
                EntryLearningPipeline.upsertSemanticEntry(entry)
                JournalSpotlightIndexer.shared.upsert(entry: entry)
            }
        } catch {
            viewContext.rollback()
        }
    }

    private func clearTimelineCache() {
        filteredEntriesCache = []
        groupedEntriesCache = [:]
        sectionKeysCache = []
        summaryEntriesCache = []
        entryMetricsCache = [:]
    }

    private func sectionTitle(for key: SectionKey) -> String {
        var comps = DateComponents()
        comps.year = key.year
        comps.month = key.month
        let calendar = Calendar.current
        if let date = calendar.date(from: comps) {
            return date.formatted(.dateTime.month(.wide).year())
        }
        return String(localized: "Unknown", comment: "Section title when an entry’s month can’t be determined.")
    }

    private func requestDelete(_ entry: DiaryEntry) {
        // Only one deletion waits for undo at a time; an earlier one is committed now.
        commitPendingDeletion()
        withOffRecordAnimation(OffRecordMotion.snappy) {
            pendingDeletion = PendingTimelineDeletion(objectID: entry.objectID, entryID: entry.id)
        }
        if selectedEntry?.objectID == entry.objectID {
            selectedEntry = nil
        }
        HapticManager.shared.entryDeleted()
        let deletionID = pendingDeletion?.id
        Task {
            try? await Task.sleep(for: .seconds(UIAccessibility.isVoiceOverRunning ? 12 : 6))
            guard pendingDeletion?.id == deletionID else { return }
            commitPendingDeletion()
        }
    }

    private func undoPendingDeletion() {
        withOffRecordAnimation(OffRecordMotion.snappy) {
            pendingDeletion = nil
        }
        HapticManager.shared.selectionChanged()
    }

    private func commitPendingDeletion() {
        guard let deletion = pendingDeletion else { return }
        pendingDeletion = nil
        guard let entry = try? viewContext.existingObject(with: deletion.objectID) as? DiaryEntry else { return }
        let plan = JournalBlockTimelineStore.prepareDeleteWholeDay(entry, in: viewContext)
        do {
            try viewContext.save()
            plan.fileURLsToRemoveAfterSave.forEach { try? FileManager.default.removeItem(at: $0) }
            if let deletedID = deletion.entryID {
                SemanticMemoryIndexController.shared.deleteEntry(id: deletedID)
                JournalSpotlightIndexer.shared.delete(entryID: deletedID)
                if routedEntry?.id == deletedID {
                    routedEntry = nil
                    navigationRouter.clearEntryRouteIfNeeded(deletedID)
                }
            }
        } catch {
            viewContext.rollback()
        }
    }

    private func toggleStar(_ entry: DiaryEntry) {
        entry.isStarred.toggle()
        do {
            try viewContext.save()
            JournalSpotlightIndexer.shared.upsert(entry: entry)
            HapticManager.shared.entryStarred()
        } catch {
            viewContext.rollback()
        }
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let label: String
    let icon: String?
    let mood: Mood?
    let style: OffRecordReadableTintStyle
    let onRemove: () -> Void

    init(
        label: String,
        icon: String? = nil,
        mood: Mood? = nil,
        style: OffRecordReadableTintStyle,
        onRemove: @escaping () -> Void
    ) {
        self.label = label
        self.icon = icon
        self.mood = mood
        self.style = style
        self.onRemove = onRemove
    }

    var body: some View {
        HStack(spacing: 4) {
            if let mood {
                MiniMoodIcon(mood: mood, size: 14, opacity: 0.92)
            } else if let icon {
                Image(systemName: icon)
                    .font(OffRecordTypography.annotation)
            }
            Text(label)
                .font(OffRecordTypography.metadata)
            Button {
                withOffRecordAnimation(OffRecordMotion.snappy) {
                    onRemove()
                }
                HapticManager.shared.buttonTap()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(OffRecordTypography.metadata)
            }
            .accessibilityLabel("Remove \(label)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .foregroundColor(style.foreground)
        .offRecordGlassControl(
            tint: style.tint,
            in: Capsule(),
            fallbackFill: style.fill,
            border: style.border
        )
    }
}

// MARK: - Date Range Button

struct DateRangeButton: View {
    let title: String
    @Binding var date: Date?
    @State private var showPicker = false
    @State private var tempDate = Date()

    var body: some View {
        Button {
            tempDate = date ?? Date()
            showPicker = true
            HapticManager.shared.buttonTap()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(OffRecordTypography.metadata)
                if let date = date {
                    Text("\(title): \(formatDate(date))")
                        .font(OffRecordTypography.metadata)
                } else {
                    Text(title)
                        .font(OffRecordTypography.metadata)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundColor(date != nil ? OffRecordReadableTintStyle.export.foreground : OffRecordColor.textSecondary)
            .offRecordGlassControl(
                tint: date != nil ? OffRecordReadableTintStyle.export.tint : nil,
                in: Capsule(),
                fallbackFill: date != nil ? OffRecordReadableTintStyle.export.fill : OffRecordReadableTintStyle.neutral.fill,
                border: date != nil ? OffRecordReadableTintStyle.export.border : OffRecordReadableTintStyle.neutral.border
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showPicker) {
            NavigationView {
                DatePicker(
                    "Select Date",
                    selection: $tempDate,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .padding()
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showPicker = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            date = tempDate
                            showPicker = false
                            HapticManager.shared.selectionChanged()
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Supporting views

struct PendingTimelineDeletion: Equatable {
    let id = UUID()
    let objectID: NSManagedObjectID
    let entryID: UUID?
}

struct TimelineUndoToast: View {
    let message: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: OffRecordSpacing.md) {
            Image(systemName: "trash")
                .foregroundStyle(OffRecordColor.textCoral)
                .accessibilityHidden(true)
            Text(message)
                .font(OffRecordTypography.labelMedium)
                .foregroundStyle(OffRecordColor.textPrimary)
                .lineLimit(2)
            Spacer(minLength: 0)
            Button("Undo", action: onUndo)
                .font(OffRecordTypography.labelLarge)
                .foregroundStyle(OffRecordColor.textLavender)
                .frame(minHeight: OffRecordLayout.minimumTapTarget)
                .accessibilityIdentifier("timeline.undoDelete")
        }
        .padding(.horizontal, OffRecordSpacing.lg)
        .padding(.vertical, OffRecordSpacing.xs)
        .frame(maxWidth: 520)
        .offRecordGlassBar(cornerRadius: OffRecordRadius.xl, fallbackFill: OffRecordColor.surfacePrimary)
        .accessibilityElement(children: .contain)
        .onAppear {
            UIAccessibility.post(notification: .announcement, argument: String(localized: "\(message). Undo available.", comment: "VoiceOver announcement. The argument is what was just done, like “Entry deleted”."))
        }
    }
}

struct TimelineSectionHeader: View {
    let title: String
    let count: Int?
    let systemImage: String?

    var body: some View {
        HStack(spacing: OffRecordSpacing.md) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(OffRecordTypography.titleSmall)
                    .foregroundStyle(OffRecordColor.textLavender)
                    .accessibilityHidden(true)
            } else {
                CalendarSectionIcon()
            }
            Text(title)
                .font(OffRecordTypography.titleMedium)
                .foregroundStyle(OffRecordColor.textBrand)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            if let count {
                Text("^[\(count) entry](inflect: true)")
                    .font(OffRecordTypography.labelMedium)
                    .foregroundStyle(OffRecordColor.textSecondary)
            }
        }
        .padding(.vertical, OffRecordSpacing.sm)
    }
}

/// Invitation shown before any entry exists — distinct from "no search results".
private struct TimelineFirstEntryState: View {
    @ObservedObject private var capture = CaptureController.shared

    var body: some View {
        VStack(spacing: OffRecordSpacing.lg) {
            FridayMascotView(pose: .wave, size: 88)
                .accessibilityHidden(true)
            VStack(spacing: OffRecordSpacing.sm) {
                Text("No Entries Yet")
                    .font(OffRecordTypography.titleSmall)
                    .foregroundStyle(OffRecordColor.textHeading)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("timeline.emptyTitle")
                Text("Your entries will show up here.")
                    .font(OffRecordTypography.bodySmall)
                    .foregroundStyle(OffRecordColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
            Button {
                capture.startRecording()
            } label: {
                Label(String(localized: "Record", comment: "Button that starts a voice recording."), systemImage: "mic.fill")
                    .offRecordPillButton()
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, OffRecordSpacing.section)
        .padding(.horizontal, OffRecordSpacing.xl)
        .offRecordCard(fill: OffRecordColor.surfacePrimary.opacity(0.85))
    }
}

/// Larger read-only preview shown when long-pressing an entry.
private struct TimelineEntryContextPreview: View {
    let entry: DiaryEntry

    var body: some View {
        let mood = Mood(rawValue: entry.mood ?? "") ?? .none
        VStack(alignment: .leading, spacing: OffRecordSpacing.md) {
            HStack(spacing: OffRecordSpacing.sm) {
                if mood != .none {
                    mood.miniImage
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                }
                Text((entry.date ?? Date()).formatted(date: .complete, time: .omitted))
                    .font(OffRecordTypography.labelMedium)
                    .foregroundStyle(OffRecordColor.textSecondary)
            }
            Text(TimelineEntryPreviewSanitizer.sanitize(entry.text ?? "").isEmpty
                 ? String(localized: "No text")
                 : TimelineEntryPreviewSanitizer.sanitize(entry.text ?? ""))
                .font(OffRecordTypography.journalBody)
                .foregroundStyle(OffRecordColor.textPrimary)
                .lineLimit(12)
        }
        .padding(OffRecordSpacing.xl)
        .frame(width: 340, alignment: .leading)
        .background(OffRecordColor.surfacePrimary)
    }
}

private extension View {
    func timelineRowLayout(maxWidth: CGFloat, bottom: CGFloat) -> some View {
        frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
            .listRowInsets(EdgeInsets(top: 0, leading: OffRecordSpacing.screenX, bottom: bottom, trailing: OffRecordSpacing.screenX))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    func timelineHeaderLayout(maxWidth: CGFloat) -> some View {
        frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, OffRecordSpacing.screenX)
            .listRowInsets(EdgeInsets())
            .background(OffRecordAppBackground().opacity(0.96))
    }
}
