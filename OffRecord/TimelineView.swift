//
//  TimelineView.swift
//  OffRecord
//
//  Displays all diary entries in a chronological timeline.
//  Supports search, filtering by starred entries, mood, date range, and swipe-to-delete.
//

import SwiftUI
import CoreData
#if os(iOS)
import Speech
#endif

/// Displays all diary entries grouped by month.
/// Supports search, starred filter, mood filter, date range, and pull-to-refresh.
struct TimelineView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
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
    @State private var searchSuggestions: [FridayAssistantEngine.SearchSuggestion] = []
    @State private var semanticResults: [UUID: EvidenceReference] = [:]
    @State private var semanticSearchQuery: String = ""
    @State private var semanticSearchTask: Task<Void, Never>?
    @State private var isSemanticSearching = false
    @State private var semanticSearchMessage: String?

    #if os(iOS)
    @StateObject private var voiceSearch = VoiceSearchManager()
    #endif

    private var assistant: FridayAssistantEngine { FridayAssistantEngine.shared }

    var body: some View {
        VStack(spacing: 0) {
            // Quick filter chips (when search is empty)
            if searchText.isEmpty && !showFilters {
                quickFilterChips
            }

            // Filter bar (when active)
            if showFilters {
                filterBar
            }
            
            // Active filters summary
            if hasActiveFilters {
                activeFiltersBar
            }

            semanticSearchStatusBanner
            
            // Entry list
                List {
                ForEach(sectionKeys, id: \.self) { key in
                    if let sectionEntries = groupedEntries[key] {
                        Section(header: Text(sectionTitle(for: key)).foregroundColor(OffRecordColor.textBrand)) {
                            ForEach(sectionEntries) { entry in
                                NavigationLink {
                                    EntryDetailView(entry: entry)
                                } label: {
                                    EntryRowView(
                                        entry: entry,
                                        searchText: searchText,
                                        dateString: entryDateString(entry),
                                        evidence: entry.id.flatMap { semanticResults[$0] }
                                    )
                                }
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            }
                            .onDelete { indexSet in
                                delete(entries: sectionEntries, at: indexSet)
                            }
                        }
                    }
                }
                
                // Empty state
                if filteredEntries.isEmpty {
                    emptySearchState
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search entries")
        .refreshable {
            HapticManager.shared.pullToRefresh()
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 12) {
                    // Voice search button
                    Button {
                        toggleVoiceSearch()
                    } label: {
                        Image(systemName: isListening ? "mic.fill" : "mic")
                            .foregroundColor(isListening ? OffRecordColor.textCoral : OffRecordColor.textBrand)
                    }
                    .accessibilityLabel("Voice search")
                    
                    // Filter button
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showFilters.toggle()
                        }
                        HapticManager.shared.buttonTap()
                    } label: {
                        Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel("Filters")
                    
                    EditButton()
                }
            }
            #endif
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    showStarredOnly.toggle()
                    HapticManager.shared.selectionChanged()
                }) {
                    Image(systemName: showStarredOnly ? "star.fill" : "star")
                        .foregroundColor(showStarredOnly ? OffRecordColor.textYellow : OffRecordColor.textBrand)
                }
                .accessibilityLabel("Show starred only")
            }
        }
        .background(OffRecordColor.appBackgroundGradient)
        .navigationTitle("Timeline")
        #if os(iOS)
        .onChange(of: voiceSearch.transcribedText) { _, newValue in
            if !newValue.isEmpty {
                searchText = newValue
                isListening = false
            }
        }
        #endif
        .onChange(of: searchText) { _, newValue in
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
        .searchSuggestions {
            ForEach(searchSuggestions, id: \.text) { suggestion in
                Button {
                    if suggestion.type == "mood" {
                        // Apply mood filter
                        if let mood = Mood(rawValue: suggestion.text.lowercased()) {
                            selectedMoodFilter = mood
                            searchText = ""
                        }
                    } else {
                        searchText = suggestion.text
                    }
                } label: {
                    Label(suggestion.text, systemImage: suggestion.icon)
                }
                .searchCompletion(suggestion.text)
            }
        }
    }

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
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(OffRecordColor.surfaceWarm)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("semanticMemory.buildingTitle")
        } else if !trimmed.isEmpty, let semanticSearchMessage {
            Text(semanticSearchMessage)
                .font(.caption)
                .foregroundColor(OffRecordColor.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(OffRecordColor.surfaceWarm)
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
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        VStack(spacing: 12) {
            // Mood filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Text("Mood:")
                        .font(.caption)
                        .foregroundColor(OffRecordColor.textSecondary)
                    
                    ForEach(Mood.allCases.filter { $0 != .none }, id: \.self) { mood in
                        Button {
                            withAnimation {
                                if selectedMoodFilter == mood {
                                    selectedMoodFilter = nil
                                } else {
                                    selectedMoodFilter = mood
                                }
                            }
                            HapticManager.shared.selectionChanged()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: mood.icon)
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
                .padding(.horizontal)
            }
            
            // Date range
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
            .padding(.horizontal)
        }
        .padding(.vertical, 12)
        .offRecordGlassBar(cornerRadius: 0, fallbackFill: OffRecordColor.surfaceWarm)
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
                    FilterChip(label: mood.rawValue, icon: mood.icon, style: mood.readableStyle) {
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
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .offRecordGlassBar(cornerRadius: 0)
    }
    
    // MARK: - Empty State
    
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
        .listRowBackground(Color.clear)
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
        }
        HapticManager.shared.buttonTap()
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
            
            // Starred filter
            if showStarredOnly && !entry.isStarred { return false }
            
            // Mood filter
            if let moodFilter = selectedMoodFilter {
                let entryMood = entry.value(forKey: "mood") as? String ?? ""
                if entryMood != moodFilter.rawValue { return false }
            }
            
            // Date range filter
            if let start = startDate {
                let startOfDay = Calendar.current.startOfDay(for: start)
                if entryDate < startOfDay { return false }
            }
            if let end = endDate {
                let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: end)) ?? end
                if entryDate >= endOfDay { return false }
            }
            
            // Text search
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

    private func sectionTitle(for key: SectionKey) -> String {
        var comps = DateComponents()
        comps.year = key.year
        comps.month = key.month
        let calendar = Calendar.current
        if let date = calendar.date(from: comps) {
            let formatter = DateFormatter()
            formatter.dateFormat = "LLLL yyyy" // e.g. December 2025
            return formatter.string(from: date)
        }
        return "Unknown"
    }

    private func entryDateString(_ entry: DiaryEntry) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: entry.date ?? Date())
    }

    private func delete(entries: [DiaryEntry], at offsets: IndexSet) {
        let deletedIDs = offsets.compactMap { entries[$0].id }
        for index in offsets {
            let entry = entries[index]
            viewContext.delete(entry)
        }
        do {
            try viewContext.save()
            deletedIDs.forEach { SemanticMemoryIndexController.shared.deleteEntry(id: $0) }
            HapticManager.shared.entryDeleted()
        } catch {
            // ignore for now
        }
    }
}

// MARK: - Entry Row View with Search Highlighting

struct EntryRowView: View {
    let entry: DiaryEntry
    let searchText: String
    let dateString: String
    let evidence: EvidenceReference?

    private var wordCount: Int {
        guard let text = entry.text, !text.isEmpty else { return 0 }
        return text.split { $0.isWhitespace || $0.isNewline }.count
    }

    private var hasPhotos: Bool {
        !PhotoStorageManager.shared.attachments(for: entry).isEmpty
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(dateString)
                        .font(.subheadline)
                        .foregroundColor(OffRecordColor.textPeach)

                    if let moodString = entry.value(forKey: "mood") as? String,
                       let mood = Mood(rawValue: moodString),
                       mood != .none {
                        Image(systemName: mood.icon)
                            .font(.caption)
                            .foregroundColor(mood.color)
                    }

                    if wordCount > 0 {
                        Text("\(wordCount) words")
                            .font(.caption)
                            .foregroundColor(OffRecordColor.textSecondary)
                    }

                    if hasPhotos {
                        Image(systemName: "photo")
                            .font(.caption)
                            .foregroundColor(OffRecordColor.textSecondary)
                    }
                }

                if let text = entry.text, !text.isEmpty {
                    highlightedText(evidence?.snippet ?? text)
                        .lineLimit(2)
                        .accessibilityIdentifier(evidence == nil ? "timeline.entrySnippet" : "timeline.evidenceSnippet")
                } else {
                    Text("Tap to add text")
                        .foregroundColor(OffRecordColor.textSecondary)
                        .italic()
                }
            }
            Spacer()
            if let evidence {
                VStack(alignment: .trailing, spacing: 4) {
                    Image(systemName: evidence.matchReason == .exact ? "text.magnifyingglass" : "brain.head.profile")
                        .foregroundColor(OffRecordColor.brandLavenderDark)
                    Text(evidence.matchReason.rawValue)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(OffRecordColor.textLavender)
                        .multilineTextAlignment(.trailing)
                }
                .accessibilityIdentifier("timeline.evidenceReason.\(evidence.matchReason.rawValue)")
            }
            if entry.isStarred {
                Image(systemName: "star.fill")
                    .foregroundColor(OffRecordColor.textYellow)
                    .font(.caption)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: OffRecordRadius.md, style: .continuous)
                .fill(OffRecordColor.surfaceWarm)
                .overlay(
                    RoundedRectangle(cornerRadius: OffRecordRadius.md, style: .continuous)
                        .stroke(OffRecordColor.borderSoft, lineWidth: 1)
                )
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("timeline.entryRow")
    }

    @ViewBuilder
    private func highlightedText(_ text: String) -> some View {
        if searchText.isEmpty {
            Text(text)
                .font(.subheadline)
                .foregroundColor(OffRecordColor.textPrimary)
        } else {
            Text(attributedString(for: text))
                .font(.subheadline)
                .foregroundColor(OffRecordColor.textPrimary)
        }
    }

    private func attributedString(for text: String) -> AttributedString {
        var attributedString = AttributedString(text)
        let searchLower = searchText.lowercased()
        let textLower = text.lowercased()

        var searchStart = textLower.startIndex
        while let range = textLower.range(of: searchLower, range: searchStart..<textLower.endIndex) {
            if let attrRange = Range(range, in: attributedString) {
                attributedString[attrRange].backgroundColor = OffRecordColor.brandYellow.opacity(0.32)
                attributedString[attrRange].foregroundColor = OffRecordColor.textPrimary
            }
            searchStart = range.upperBound
        }

        return attributedString
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let label: String
    let icon: String
    let style: OffRecordReadableTintStyle
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
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
