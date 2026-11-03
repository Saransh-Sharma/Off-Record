//
//  EntryDetailView.swift
//  OffRecord
//
//  Detail view for viewing and editing a single diary entry.
//  Supports text editing, mood selection, and audio playback.
//

import SwiftUI
import AVFoundation
import CoreData
import JournalFoundation
import PhotosUI
import os.log

private let entryDetailLogger = Logger(subsystem: "com.singularity.offrecord", category: "EntryDetail")

/// Detail view for a single diary entry.
/// Allows viewing, editing text, setting mood, playing back audio, and attaching photos.
struct EntryDetailView: View {
    @ObservedObject var entry: DiaryEntry
    @ObservedObject var entryTitles = EntryTitleStore.shared
    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) var dismiss
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @FocusState var isTextFocused: Bool

    @State var text: String
    @State var selectedMood: Mood
    @State var showMoodPicker = false
    @State var hasEditedText = false
    @State var showAIInsights = false
    @State var aiAnalysis: EntryInsight?
    @State var journalBlocks: [JournalBlock] = []
    @State var timelineItems: [JournalBlockTimelineItem] = []
    @State var editingBlockObjectID: NSManagedObjectID?
    @State var editingBlockText = ""
    @State var blockEditError: String?
    @State var isComposingTextBlock = false
    @State var newTextBlockText = ""
    @State var newTextBlockError: String?
    @State var showDeleteDayConfirm = false
    @State var pendingBlockDeletion: JournalBlockTimelineItem?
    @State var deeperQuestion: String?
    @State var isFetchingDeeperQuestion = false
    @State var composerPrompt: String?
    @State private var isDeletingDay = false
    @AppStorage(FridayAvailability.defaultsKey) private var isFridayEnabled = true
    private let deleteEmptyDraftOnDisappear: Bool
    let promptContext: String?
    let heroPromptID: String?
    let showsDismissButton: Bool
    @State private var currentActivity: NSUserActivity?

    // Photo state
    @State var selectedPhotos: [PhotosPickerItem] = []
    @State var photoAttachments: [PhotoAttachment] = []
    @State var photoAttachmentByID: [UUID: PhotoAttachment] = [:]
    #if canImport(UIKit)
    @State var photoImages: [UIImage] = []
    @State var photoThumbnailByID: [UUID: UIImage] = [:]
    #endif

    var isIPad: Bool { horizontalSizeClass == .regular }
    /// Go Deeper and entry insights need Friday on and this entry not kept out of her.
    private var fridayReadsEntry: Bool { isFridayEnabled && entry.journalAIExclusion.permitsAssistantEvidence }
    private var compactMoodPickerBinding: Binding<Bool> {
        Binding(
            get: { showMoodPicker && !isIPad },
            set: { if !$0 { showMoodPicker = false } }
        )
    }
    private var regularMoodPickerBinding: Binding<Bool> {
        Binding(
            get: { showMoodPicker && isIPad },
            set: { if !$0 { showMoodPicker = false } }
        )
    }

    init(
        entry: DiaryEntry,
        startEditing: Bool = false,
        deleteEmptyDraftOnDisappear: Bool = false,
        promptContext: String? = nil,
        heroPromptID: String? = nil,
        showsDismissButton: Bool = true
    ) {
        self.entry = entry
        self.deleteEmptyDraftOnDisappear = deleteEmptyDraftOnDisappear
        self.promptContext = promptContext
        self.heroPromptID = heroPromptID
        self.showsDismissButton = showsDismissButton
        _text = State(initialValue: entry.text ?? "")
        _isComposingTextBlock = State(initialValue: startEditing)
        let moodString = entry.value(forKey: "mood") as? String ?? ""
        _selectedMood = State(initialValue: Mood(rawValue: moodString) ?? .none)
    }

    var body: some View {
        ZStack {
            OffRecordAppBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: OffRecordSpacing.lg) {
                    journalEntryTopBar
                        .padding(.top, 12)

                    detailDateTitle

                    daySummaryCard

                    EntryTagsRow(entry: entry)

                    if isComposingTextBlock {
                        newTextBlockComposer
                    }

                    journalTimelineView

                    EntryAIExclusionNote(exclusion: entry.journalAIExclusion)

                    if !isComposingTextBlock {
                        if !text.isEmpty {
                            switch entryResponseMode {
                            case .normal:
                                if fridayReadsEntry { goDeeperCard }
                            case .gentle:
                                // Heavy entries get no probing question.
                                EmptyView()
                            case .supportOnly:
                                entrySupportCard
                            }
                        }
                        addToDaySection
                    }

                    if !text.isEmpty, entryResponseMode != .supportOnly, fridayReadsEntry {
                        aiInsightsSection
                    }
                }
                .padding(.horizontal, OffRecordSpacing.screenX)
                .padding(.top, 4)
                .padding(.bottom, isActivelyEditing ? 160 : 96)
            }
            .scrollDismissesKeyboard(.interactively)
            .frame(maxWidth: isIPad ? 860 : .infinity)
            .frame(maxWidth: .infinity)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(showsDismissButton ? .hidden : .visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .onScreenJournalEntry(entry.isStartedEntry ? entry.id : nil)
        .confirmationDialog(
            blockDeletionTitle(for: pendingBlockDeletion?.kind),
            isPresented: Binding(
                get: { pendingBlockDeletion != nil },
                set: { if !$0 { pendingBlockDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingBlockDeletion
        ) { item in
            Button(item.kind == .mood ? "Remove" : "Delete", role: .destructive) {
                deleteBlock(item)
            }
            Button("Cancel", role: .cancel) {}
        } message: { item in
            Text(item.kind == .audio ? "The audio and transcript will be deleted." : "This can’t be undone.")
        }
        .confirmationDialog(
            "Delete This Entry?",
            isPresented: $showDeleteDayConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Entry", role: .destructive) {
                deleteWholeDay()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its text, recordings, photos, and moods will be deleted. This can’t be undone.")
        }
        .onDisappear {
            if !isDeletingDay {
                let canDeleteEmptyDraft = savePendingEditsBeforeExit()
                saveIfNeeded()
                if canDeleteEmptyDraft {
                    deleteEmptyDraftIfNeeded()
                }
            }
            currentActivity?.resignCurrent()
            currentActivity = nil
            clearPhotoThumbnails()
            // Recording from the accessory goes back to today once this day is closed.
            let capture = CaptureController.shared
            if !capture.phase.isCapturing {
                capture.captureDate = Date()
                capture.resetCaptureJournal()
            }
        }
        .onAppear {
            // While a day is open, the capture accessory records into that day.
            if let date = entry.date, !CaptureController.shared.phase.isCapturing {
                CaptureController.shared.captureDate = date
                CaptureController.shared.captureJournalID = entry.journal?.id
            }
            loadPhotos()
            loadBlocks(backfill: true)
            startEntryActivity()
            syncTextFromEntry(reason: "appear")
            entryTitles.requestTitle(for: entry)
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                clearPhotoThumbnails()
            case .active:
                loadPhotos()
            default:
                break
            }
        }
        .onChange(of: selectedPhotos) { _, newItems in
            handlePhotoSelection(newItems)
        }
        .onChange(of: entry.text) { _, newValue in
            syncTextFromEntry(reason: "textChanged", incomingText: newValue)
        }
        .onChange(of: entry.updatedAt) { _, _ in
            syncTextFromEntry(reason: "updatedAtChanged")
            loadBlocks(backfill: false)
            entryTitles.requestTitle(for: entry)
        }
        .onChange(of: entry.entryTranscriptionStatus) { _, _ in
            syncTextFromEntry(reason: "transcriptionStatusChanged")
        }
        .fullScreenCover(isPresented: compactMoodPickerBinding) {
            MoodDialSheet(selectedMood: $selectedMood, onSave: saveMood)
                .offRecordMoodDialEnvironment()
        }
        .sheet(isPresented: regularMoodPickerBinding) {
            MoodDialSheet(selectedMood: $selectedMood, onSave: saveMood)
                .presentationDetents([.large])
                .offRecordMoodDialEnvironment()
        }
    }

    private func blockDeletionTitle(for kind: JournalBlockKind?) -> String {
        switch kind {
        case .audio: return String(localized: "Delete Recording?")
        case .text: return String(localized: "Delete Text?")
        case .photo: return String(localized: "Delete Photo?")
        case .mood: return String(localized: "Remove Mood?")
        case nil: return String(localized: "Delete?")
        }
    }

    private func removeFilesAfterSuccessfulSave(_ urls: [URL]) {
        for url in urls where FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func deleteBlock(_ item: JournalBlockTimelineItem) {
        guard let block = block(for: item) else { return }
        let plan = JournalBlockTimelineStore.deleteBlock(block, in: viewContext)
        do {
            try viewContext.save()
            removeFilesAfterSuccessfulSave(plan.fileURLsToRemoveAfterSave)
            EntryLearningPipeline.upsertSemanticEntry(entry)
            JournalSpotlightIndexer.shared.upsert(entry: entry)
            HapticManager.shared.entryDeleted()
        } catch {
            viewContext.rollback()
        }
        loadPhotos()
        loadBlocks(backfill: false)
    }

    private func deleteWholeDay() {
        isDeletingDay = true
        let plan = JournalBlockTimelineStore.prepareDeleteWholeDay(entry, in: viewContext)
        do {
            try viewContext.save()
            removeFilesAfterSuccessfulSave(plan.fileURLsToRemoveAfterSave)
            if let id = plan.entryID {
                SemanticMemoryIndexController.shared.deleteEntry(id: id)
                JournalSpotlightIndexer.shared.delete(entryID: id)
            }
            HapticManager.shared.entryDeleted()
            dismiss()
        } catch {
            isDeletingDay = false
            viewContext.rollback()
        }
    }

    private func syncTextFromEntry(reason: String, incomingText: String? = nil) {
        let persistedText = incomingText ?? entry.text ?? ""
        guard !isComposingTextBlock && editingBlockObjectID == nil && !isTextFocused else {
            entryDetailLogger.info("Skipped text sync entryID=\(entry.id?.uuidString ?? "missing", privacy: .public) reason=\(reason, privacy: .public) localChars=\(text.count, privacy: .public) persistedChars=\(persistedText.count, privacy: .public) composing=\(isComposingTextBlock, privacy: .public) status=\(entry.entryTranscriptionStatus.rawValue, privacy: .public)")
            return
        }

        guard text != persistedText else { return }

        entryDetailLogger.info("Synced text from entry entryID=\(entry.id?.uuidString ?? "missing", privacy: .public) reason=\(reason, privacy: .public) localChars=\(text.count, privacy: .public) persistedChars=\(persistedText.count, privacy: .public) status=\(entry.entryTranscriptionStatus.rawValue, privacy: .public)")
        text = persistedText
        hasEditedText = false
    }

    private func saveIfNeeded() {
        guard !isDeletingDay else { return }
        let currentMood = entry.value(forKey: "mood") as? String ?? ""
        let moodChanged = selectedMood.rawValue != currentMood
        if moodChanged, selectedMood != .none {
            JournalBlockTimelineStore.appendMoodBlock(
                mood: selectedMood,
                createdAt: entryTimestampNow(),
                to: entry,
                in: viewContext
            )
            entry.updatedAt = Date()
            do {
                try viewContext.save()
                EntryLearningPipeline.upsertSemanticEntry(entry)
                JournalSpotlightIndexer.shared.upsert(entry: entry)
                loadBlocks(backfill: false)
            } catch {
                viewContext.rollback()
            }
        }
    }

    private func deleteEmptyDraftIfNeeded() {
        guard deleteEmptyDraftOnDisappear, entryHasNoContent else { return }

        let id = entry.id
        viewContext.delete(entry)
        do {
            try viewContext.save()
            SemanticMemoryIndexController.shared.deleteEntry(id: id)
            JournalSpotlightIndexer.shared.delete(entryID: id)
        } catch {
            viewContext.rollback()
        }
    }

    private var entryHasNoContent: Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let persistedText = entry.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let duration = entry.value(forKey: "duration") as? Double ?? 0
        let photoCount = entry.photos?.count ?? 0
        let blockCount = journalBlocks.count
        let hasSelectedMood = selectedMood != .none || entry.hasStartedEntryMood
        return trimmed.isEmpty
            && persistedText.isEmpty
            && !hasAudioReference
            && duration <= 0
            && photoCount == 0
            && blockCount == 0
            && !hasSelectedMood
    }

    private func saveMood() {
        JournalBlockTimelineStore.appendMoodBlock(
            mood: selectedMood,
            createdAt: entryTimestampNow(),
            to: entry,
            in: viewContext
        )
        entry.updatedAt = Date()
        HapticManager.shared.moodSelected()
        do {
            try viewContext.save()
            EntryLearningPipeline.upsertSemanticEntry(entry)
            JournalSpotlightIndexer.shared.upsert(entry: entry)
            loadBlocks(backfill: false)
        } catch {
            // ignore
        }
    }

    private func startEntryActivity() {
        currentActivity?.resignCurrent()
        currentActivity = JournalSpotlightIndexer.shared.activity(for: entry)
        currentActivity?.becomeCurrent()
    }

    func entryTimestampNow(clock: Date = Date()) -> Date {
        let calendar = Calendar.current
        let base = entry.date ?? clock
        let day = calendar.dateComponents([.year, .month, .day], from: base)
        let time = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: clock)
        var components = DateComponents()
        components.calendar = calendar
        components.year = day.year
        components.month = day.month
        components.day = day.day
        components.hour = time.hour
        components.minute = time.minute
        components.second = time.second
        components.nanosecond = time.nanosecond
        return calendar.date(from: components) ?? clock
    }
}
