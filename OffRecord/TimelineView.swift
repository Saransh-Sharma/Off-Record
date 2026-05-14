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
    @ObservedObject private var semanticMemory = SemanticMemoryIndexController.shared

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \DiaryEntry.date, ascending: false)],
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
    @State private var isEditingTimeline: Bool = false
    @State private var searchSuggestions: [FridayAssistantEngine.SearchSuggestion] = []
    @State private var semanticResults: [UUID: EvidenceReference] = [:]
    @State private var semanticSearchQuery: String = ""
    @State private var semanticSearchTask: Task<Void, Never>?
    @State private var isSemanticSearching = false
    @State private var semanticSearchMessage: String?
    @State private var isSearchFocused = false

    #if os(iOS)
    @StateObject private var voiceSearch = VoiceSearchManager()
    #endif

    private var assistant: FridayAssistantEngine { FridayAssistantEngine.shared }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TimelineDesign.contentSpacing) {
                timelineHeader
                searchArea

                if showFilters {
                    filterBar
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if hasActiveFilters {
                    activeFiltersBar
                        .transition(.opacity)
                }

                semanticSearchStatusBanner

                if !filteredEntries.isEmpty {
                    MonthSummaryCard(entries: summaryEntries)
                }

                timelineContent
            }
            .frame(maxWidth: TimelineDesign.maxContentWidth)
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity)
        }
        .refreshable {
            HapticManager.shared.pullToRefresh()
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        .background(OffRecordColor.appBackgroundGradient.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        #if os(iOS)
        .onChange(of: voiceSearch.transcribedText) { _, newValue in
            if !newValue.isEmpty {
                searchText = newValue
                isListening = false
            }
        }
        #endif
        .onChange(of: searchText) { _, newValue in
            handleSearchTextChanged(newValue)
        }
        .onChange(of: semanticMemory.isBuilding) { _, isBuilding in
            guard !isBuilding else { return }
            let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count >= 2, isSemanticSearching {
                scheduleSemanticSearch(trimmed)
            }
        }
        .onAppear {
            semanticMemory.ensureIndexed(entries: Array(entries))
        }
    }

    // MARK: - Header

    private var timelineHeader: some View {
        ZStack(alignment: .topTrailing) {
            Image("CreeperPlant01")
                .resizable()
                .scaledToFit()
                .frame(width: dynamicTypeSize.isAccessibilitySize ? 102 : TimelineDesign.planterWidth)
                .offset(x: -4, y: 40)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .zIndex(0)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Button {
                        showStarredOnly.toggle()
                        HapticManager.shared.selectionChanged()
                    } label: {
                        Image(systemName: showStarredOnly ? "star.fill" : "star")
                            .font(.system(size: 25, weight: .medium))
                            .foregroundStyle(showStarredOnly ? OffRecordColor.textYellow : OffRecordColor.textBrand)
                            .frame(width: 56, height: 56)
                            .background(Circle().fill(OffRecordColor.surfacePrimary.opacity(0.78)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Show starred only")

                    Spacer(minLength: 12)

                    headerActions
                }

                Text("Timeline")
                    .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 46 : 56, weight: .black, design: .serif))
                    .foregroundStyle(OffRecordColor.textBrand)
                    .minimumScaleFactor(0.72)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, dynamicTypeSize.isAccessibilitySize ? 34 : 20)
            }
            .zIndex(1)
        }
        .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 132 : 108)
    }

    private var headerActions: some View {
        HStack(spacing: 12) {
            #if os(iOS)
            Button {
                toggleVoiceSearch()
            } label: {
                Image(systemName: isListening ? "mic.fill" : "mic")
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(isListening ? OffRecordColor.textCoral : OffRecordColor.textBrand)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(OffRecordColor.surfacePrimary.opacity(0.82)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Voice search")
            #endif

            HStack(spacing: 14) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showFilters.toggle()
                    }
                    HapticManager.shared.buttonTap()
                } label: {
                    Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(OffRecordColor.brandLavenderDark)
                        .frame(width: 30, height: 34)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Filters")

                Rectangle()
                    .fill(OffRecordColor.divider)
                    .frame(width: 1, height: 34)

                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        isEditingTimeline.toggle()
                    }
                    HapticManager.shared.buttonTap()
                } label: {
                    Text(isEditingTimeline ? "Done" : "Edit")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(OffRecordColor.brandLavenderDark)
                        .frame(minWidth: 48, alignment: .center)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isEditingTimeline ? "Done editing" : "Edit timeline")
            }
            .padding(.horizontal, 18)
            .frame(height: 56)
            .background(Capsule().fill(OffRecordColor.surfacePrimary.opacity(0.84)))
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
                            .font(.caption.weight(.medium))
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
                Text("Building semantic memory")
                    .font(.caption.weight(.semibold))
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
                .font(.caption)
                .foregroundColor(OffRecordColor.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(OffRecordColor.surfaceWarm, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .accessibilityIdentifier("semanticMemory.searchMessage")
        }
    }

    // MARK: - Quick Filter Chips

    private var quickFilterChips: some View {
        let topPeople = assistant.knowledgeGraph.topNodes(ofType: .person, limit: 3)
        let topTopics = assistant.knowledgeGraph.topNodes(ofType: .topic, limit: 3)
        let chips = topPeople + topTopics

        return Group {
            if !chips.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(chips, id: \.id) { node in
                            Button {
                                searchText = node.label
                                HapticManager.shared.selectionChanged()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: node.type == .person ? "person.fill" : "tag.fill")
                                        .font(.caption2)
                                    Text(node.label)
                                        .font(.caption)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .foregroundColor(OffRecordReadableTintStyle.privacy.foreground)
                                .offRecordGlassControl(
                                    tint: OffRecordReadableTintStyle.privacy.tint,
                                    in: Capsule(),
                                    fallbackFill: OffRecordReadableTintStyle.privacy.fill,
                                    border: OffRecordReadableTintStyle.privacy.border
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Text("Mood:")
                        .font(.caption)
                        .foregroundColor(OffRecordColor.textSecondary)

                    ForEach(Mood.allCases.filter { $0 != .none }, id: \.self) { mood in
                        Button {
                            withAnimation {
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
                                Text(mood.rawValue)
                            }
                            .font(.caption)
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
                DateRangeButton(title: "From", date: $startDate)
                DateRangeButton(title: "To", date: $endDate)

                Spacer()

                if startDate != nil || endDate != nil {
                    Button("Clear Dates") {
                        withAnimation {
                            startDate = nil
                            endDate = nil
                        }
                        HapticManager.shared.buttonTap()
                    }
                    .font(.caption)
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
                    FilterChip(label: "Starred", icon: "star.fill", style: .highlight) {
                        showStarredOnly = false
                    }
                }

                if let mood = selectedMoodFilter {
                    FilterChip(label: mood.rawValue, mood: mood, style: mood.readableStyle) {
                        selectedMoodFilter = nil
                    }
                }

                if let start = startDate {
                    FilterChip(label: "From \(formatShortDate(start))", icon: "calendar", style: .export) {
                        startDate = nil
                    }
                }

                if let end = endDate {
                    FilterChip(label: "To \(formatShortDate(end))", icon: "calendar", style: .export) {
                        endDate = nil
                    }
                }

                if hasActiveFilters {
                    Button("Clear All") {
                        clearAllFilters()
                    }
                    .font(.caption.weight(.medium))
                    .foregroundColor(OffRecordColor.textCoral)
                    .padding(.leading, 8)
                }
            }
        }
    }

    // MARK: - Timeline Content

    @ViewBuilder
    private var timelineContent: some View {
        if filteredEntries.isEmpty {
            emptySearchState
        } else {
            LazyVStack(alignment: .leading, spacing: 22) {
                ForEach(sectionKeys, id: \.self) { key in
                    if let sectionEntries = groupedEntries[key] {
                        TimelineMonthSection(
                            title: sectionTitle(for: key),
                            entries: sectionEntries,
                            searchText: searchText,
                            semanticResults: semanticResults,
                            isEditing: isEditingTimeline,
                            onDelete: delete(entry:)
                        )
                    }
                }
            }
        }
    }

    private var emptySearchState: some View {
        VStack(spacing: 16) {
            Image(systemName: semanticMemory.isBuilding ? "brain.head.profile" : "magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(OffRecordColor.textSecondary)

            Text(semanticMemory.isBuilding ? "Building semantic memory" : "No entries found")
                .font(.headline)
                .foregroundColor(OffRecordColor.textHeading)
                .accessibilityIdentifier(semanticMemory.isBuilding ? "semanticMemory.buildingTitle" : "timeline.emptyTitle")

            if semanticMemory.isBuilding {
                ProgressView(value: semanticMemory.progress)
                    .frame(maxWidth: 220)
                Text("Friday is indexing your journal locally. Search results will improve as this finishes.")
                    .font(.caption)
                    .foregroundColor(OffRecordColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .accessibilityIdentifier("semanticMemory.buildingMessage")
            } else if let semanticSearchMessage {
                Text(semanticSearchMessage)
                    .font(.caption)
                    .foregroundColor(OffRecordColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .accessibilityIdentifier("semanticMemory.searchMessage")
            }

            if hasActiveFilters {
                Button("Clear Filters") {
                    clearAllFilters()
                }
                .font(.subheadline)
                .foregroundColor(OffRecordColor.brandPlum)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .padding(.horizontal, 18)
        .background(OffRecordColor.surfacePrimary.opacity(0.72), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    // MARK: - Voice Search

    private func toggleVoiceSearch() {
        #if os(iOS)
        if isListening {
            voiceSearch.stopListening()
            isListening = false
        } else {
            voiceSearch.startListening()
            isListening = true
            HapticManager.shared.recordingStarted()
        }
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
            semanticSearchQuery = ""
            semanticSearchTask?.cancel()
            isSemanticSearching = false
            semanticSearchMessage = nil
        }
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
        let entrySnapshot = Array(entries)
        semanticSearchTask = Task {
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                isSemanticSearching = true
                semanticSearchQuery = query
                semanticSearchMessage = "Searching semantic memory..."
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
                    semanticSearchMessage = nil
                    isSemanticSearching = false
                case .building(_, let message):
                    semanticResults = [:]
                    semanticSearchMessage = message
                    isSemanticSearching = true
                case .unavailable(let message), .failed(let message):
                    semanticResults = [:]
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
        withAnimation {
            showStarredOnly = false
            selectedMoodFilter = nil
            startDate = nil
            endDate = nil
            searchText = ""
            semanticResults = [:]
            semanticSearchQuery = ""
            semanticSearchMessage = nil
            isEditingTimeline = false
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

    private var filteredEntries: [DiaryEntry] {
        entries.filter { entry in
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
                if semanticSearchQuery == searchTrimmed, !isSemanticSearching {
                    guard let id = entry.id else { return false }
                    if semanticResults[id] == nil { return false }
                } else {
                    let text = entry.text ?? ""
                    if !text.localizedCaseInsensitiveContains(searchTrimmed) { return false }
                }
            }

            return true
        }
    }

    private var groupedEntries: [SectionKey: [DiaryEntry]] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: filteredEntries) { (entry: DiaryEntry) -> SectionKey in
            let date = entry.date ?? Date.distantPast
            let comps = calendar.dateComponents([.year, .month], from: date)
            return SectionKey(year: comps.year ?? 0, month: comps.month ?? 0)
        }
        return groups.mapValues { entries in
            entries.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        }
    }

    private var sectionKeys: [SectionKey] {
        groupedEntries.keys.sorted { lhs, rhs in
            if lhs.year != rhs.year { return lhs.year > rhs.year }
            return lhs.month > rhs.month
        }
    }

    private var summaryEntries: [DiaryEntry] {
        guard let key = sectionKeys.first else { return [] }
        return groupedEntries[key] ?? []
    }

    private func sectionTitle(for key: SectionKey) -> String {
        var comps = DateComponents()
        comps.year = key.year
        comps.month = key.month
        let calendar = Calendar.current
        if let date = calendar.date(from: comps) {
            let formatter = DateFormatter()
            formatter.dateFormat = "LLLL yyyy"
            return formatter.string(from: date)
        }
        return "Unknown"
    }

    private func delete(entry: DiaryEntry) {
        let deletedID = entry.id
        withAnimation(.easeInOut(duration: 0.2)) {
            viewContext.delete(entry)
        }
        do {
            try viewContext.save()
            if let deletedID {
                SemanticMemoryIndexController.shared.deleteEntry(id: deletedID)
            }
            HapticManager.shared.entryDeleted()
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
                    .font(.caption2)
            }
            Text(label)
                .font(.caption)
            Button {
                withAnimation {
                    onRemove()
                }
                HapticManager.shared.buttonTap()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
            }
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
                    .font(.caption)
                if let date = date {
                    Text("\(title): \(formatDate(date))")
                        .font(.caption)
                } else {
                    Text(title)
                        .font(.caption)
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
