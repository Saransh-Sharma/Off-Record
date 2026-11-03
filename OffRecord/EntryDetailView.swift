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
    @State private var hasEditedText = false
    @State var showAIInsights = false
    @State var aiAnalysis: EntryInsight?
    @State private var journalBlocks: [JournalBlock] = []
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
    private let heroPromptID: String?
    let showsDismissButton: Bool
    @State private var currentActivity: NSUserActivity?

    // Photo state
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State var photoAttachments: [PhotoAttachment] = []
    @State private var photoAttachmentByID: [UUID: PhotoAttachment] = [:]
    #if canImport(UIKit)
    @State private var photoImages: [UIImage] = []
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

    private var addToDaySection: some View {
        VStack(alignment: .leading, spacing: OffRecordSpacing.md) {
            sectionLabel(String(localized: "Add", comment: "Section header above the Add Text and Add Photos buttons."))
            HStack(spacing: OffRecordSpacing.md) {
                addTextButton
                addPhotosButton
            }
        }
    }

    private var addTextButton: some View {
        Button {
            beginNewTextBlock()
        } label: {
            Label("Add Text", systemImage: "square.and.pencil")
                .frame(maxWidth: .infinity)
        }
        .font(OffRecordTypography.labelMedium)
        .foregroundStyle(OffRecordReadableTintStyle.brand.foreground)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 52)
        .background(OffRecordReadableTintStyle.brand.fill, in: Capsule())
        .overlay(Capsule().stroke(OffRecordReadableTintStyle.brand.border, lineWidth: 1))
    }

    private var addPhotosButton: some View {
        PhotosPicker(
            selection: $selectedPhotos,
            maxSelectionCount: 5,
            matching: .images
        ) {
            Label("Add Photos", systemImage: "photo.badge.plus")
                .font(OffRecordTypography.labelMedium)
                .foregroundStyle(OffRecordReadableTintStyle.journal.foreground)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
                .background(OffRecordReadableTintStyle.journal.fill, in: Capsule())
                .overlay(Capsule().stroke(OffRecordReadableTintStyle.journal.border, lineWidth: 1))
        }
    }

    private func loadPhotos() {
        if PhotoStorageManager.shared.migrateLegacyPhotos(for: entry, in: viewContext) {
            try? viewContext.save()
        }
        photoAttachments = PhotoStorageManager.shared.attachments(for: entry)
        photoAttachmentByID = Dictionary(uniqueKeysWithValues: photoAttachments.compactMap { attachment in
            guard let id = attachment.id else { return nil }
            return (id, attachment)
        })
        #if canImport(UIKit)
        photoImages = PhotoStorageManager.shared.thumbnailImages(for: entry)
        var thumbnails: [UUID: UIImage] = [:]
        for attachment in photoAttachments {
            guard let id = attachment.id,
                  let image = PhotoStorageManager.shared.thumbnailImage(for: attachment, maxPixelDimension: 720) else { continue }
            thumbnails[id] = image
        }
        photoThumbnailByID = thumbnails
        #endif
    }

    private func loadBlocks(backfill: Bool) {
        if backfill, JournalBlockTimelineStore.backfillBlocksIfNeeded(for: entry, in: viewContext) {
            try? viewContext.save()
        }
        journalBlocks = JournalBlockTimelineStore.blocks(for: entry)
        timelineItems = makeTimelineItems(from: journalBlocks)
        text = entry.text ?? ""
        selectedMood = Mood(rawValue: entry.value(forKey: "mood") as? String ?? "") ?? .none
    }

    private func makeTimelineItems(from blocks: [JournalBlock]) -> [JournalBlockTimelineItem] {
        let audioAttachments = Dictionary(uniqueKeysWithValues: AudioAttachmentStore.audioAttachments(for: entry).compactMap { attachment -> (UUID, NSManagedObject)? in
            guard let id = attachment.value(forKey: "id") as? UUID else { return nil }
            return (id, attachment)
        })

        return blocks.compactMap { block in
            guard let kind = block.blockKind else { return nil }
            let createdAt = block.blockCreatedAt == .distantPast ? (entry.date ?? Date()) : block.blockCreatedAt
            let timestamp = JournalBlockTimelinePresentation.label(for: createdAt)
            let mood = Mood(rawValue: block.moodValue) ?? .none
            var audioURL: URL?
            if let id = block.audioAttachmentIDValue,
               let attachment = audioAttachments[id] {
                audioURL = AudioAttachmentStore.audioURL(for: attachment)
            } else if kind == .audio {
                let legacyFileName = block.textValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !legacyFileName.isEmpty {
                    audioURL = try? AudioAttachmentStore.destinationURL(for: legacyFileName)
                }
            }

            return JournalBlockTimelineItem(
                id: block.objectID,
                blockID: block.blockID,
                kind: kind,
                createdAt: createdAt,
                sourceCaptureID: block.sourceCaptureIDValue,
                timestamp: timestamp,
                text: block.textValue,
                mood: mood,
                duration: block.durationValue,
                audioURL: audioURL,
                audioExists: audioURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false,
                photoAttachmentID: block.photoAttachmentIDValue
            )
        }
    }

    private func clearPhotoThumbnails() {
        #if canImport(UIKit)
        photoImages = []
        photoThumbnailByID = [:]
        #endif
    }

    private func handlePhotoSelection(_ items: [PhotosPickerItem]) {
        #if canImport(UIKit)
        let entryObjectID = entry.objectID
        for item in items {
            let token = PerformanceSignposts.begin("PhotoImport")
            item.loadTransferable(type: Data.self) { result in
                guard case .success(let data) = result, let data else {
                    PerformanceSignposts.end(token)
                    return
                }

                Task { @MainActor in
                    guard let jpegData = await PhotoAttachmentProcessor.shared.preparedJPEGData(from: data),
                          let image = PhotoStorageManager.thumbnailImage(from: jpegData) else {
                        PerformanceSignposts.end(token)
                        return
                    }

                    guard let entry = try? viewContext.existingObject(with: entryObjectID) as? DiaryEntry else {
                        PerformanceSignposts.end(token)
                        return
                    }

                    if let attachment = PhotoStorageManager.shared.addPhotoData(jpegData, to: entry, in: viewContext) {
                        JournalBlockTimelineStore.appendPhotoBlock(
                            attachment: attachment,
                            createdAt: entryTimestampNow(),
                            to: entry,
                            in: viewContext
                        )
                        photoAttachments.append(attachment)
                        photoImages.append(image)
                        savePhotos()
                    }
                    PerformanceSignposts.end(token)
                }
            }
        }
        selectedPhotos = []
        #endif
    }

    private func savePhotos() {
        entry.updatedAt = Date()
        try? viewContext.save()
        photoAttachments = PhotoStorageManager.shared.attachments(for: entry)
        loadBlocks(backfill: false)
        JournalSpotlightIndexer.shared.upsert(entry: entry)
    }

    // MARK: - Computed Properties

    var isActivelyEditing: Bool {
        isComposingTextBlock || editingBlockObjectID != nil
    }

    private var activeEditingItem: JournalBlockTimelineItem? {
        guard let editingBlockObjectID else { return nil }
        return timelineItems.first { $0.id == editingBlockObjectID }
    }

    var canSaveActiveEditing: Bool {
        if isComposingTextBlock {
            return !newTextBlockText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if editingBlockObjectID != nil {
            return !editingBlockText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return false
    }

    var activeWordCount: Int {
        if isComposingTextBlock {
            return wordCount(for: newTextBlockText)
        }
        if editingBlockObjectID != nil {
            return wordCount(for: editingBlockText)
        }
        return wordCount
    }

    private var wordCount: Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }

    private var characterCount: Int {
        text.count
    }

    private var editableTextBinding: Binding<String> {
        Binding(
            get: { text },
            set: { newValue in
                if text != newValue {
                    text = newValue
                    hasEditedText = true
                }
            }
        )
    }

    private func blockKind(_ block: NSManagedObject) -> JournalBlockKind? {
        JournalBlockKind(rawValue: block.value(forKey: "kind") as? String ?? "")
    }

    private func audioURL(for block: NSManagedObject) -> URL? {
        if let id = block.value(forKey: "audioAttachmentID") as? UUID,
           let attachment = AudioAttachmentStore.audioAttachment(id: id, in: viewContext) {
            return AudioAttachmentStore.audioURL(for: attachment)
        }
        if let legacyFileName = (block.value(forKey: "text") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !legacyFileName.isEmpty {
            return try? AudioAttachmentStore.destinationURL(for: legacyFileName)
        }
        return nil
    }

    private func photoAttachment(for block: NSManagedObject) -> PhotoAttachment? {
        guard let id = block.value(forKey: "photoAttachmentID") as? UUID else { return nil }
        return PhotoStorageManager.shared.attachments(for: entry).first { $0.id == id }
    }

    func block(for item: JournalBlockTimelineItem) -> JournalBlock? {
        try? viewContext.existingObject(with: item.id) as? JournalBlock
    }

    private func wordCount(for value: String) -> Int {
        value.split { $0.isWhitespace || $0.isNewline }.count
    }

    // MARK: - Actions

    private func removeFilesAfterSuccessfulSave(_ urls: [URL]) {
        for url in urls where FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func toggleEditingMode() {
        if isComposingTextBlock {
            cancelNewTextBlock()
        } else {
            beginNewTextBlock()
        }
    }

    func saveActiveEditing() {
        if isComposingTextBlock {
            _ = saveNewTextBlock()
        } else if let activeEditingItem {
            _ = finishEditingBlock(activeEditingItem)
        }
    }

    func cancelActiveEditing() {
        if isComposingTextBlock {
            cancelNewTextBlock()
        } else {
            cancelEditingBlock()
        }
    }

    private func cancelEditingBlock() {
        isTextFocused = false
        editingBlockObjectID = nil
        editingBlockText = ""
        blockEditError = nil
    }

    private func savePendingEditsBeforeExit() -> Bool {
        var didSave = true

        if let activeEditingItem {
            let trimmed = editingBlockText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                cancelEditingBlock()
            } else {
                didSave = finishEditingBlock(activeEditingItem) && didSave
            }
        }

        if isComposingTextBlock {
            let trimmed = newTextBlockText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                cancelNewTextBlock()
                return didSave
            }
            didSave = saveNewTextBlock() && didSave
        }

        return didSave
    }

    func beginNewTextBlock() {
        if editingBlockObjectID != nil {
            guard savePendingEditsBeforeExit() else { return }
        }
        newTextBlockText = ""
        newTextBlockError = nil
        isComposingTextBlock = true
        isTextFocused = true
        HapticManager.shared.selectionChanged()
    }

    private func cancelNewTextBlock() {
        isTextFocused = false
        composerPrompt = nil
        isComposingTextBlock = false
        newTextBlockText = ""
        newTextBlockError = nil
    }

    @discardableResult
    private func saveNewTextBlock() -> Bool {
        let trimmed = newTextBlockText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            newTextBlockError = String(localized: "Write something first.")
            return false
        }

        JournalBlockTimelineStore.appendTextBlock(
            text: trimmed,
            createdAt: entryTimestampNow(),
            to: entry,
            in: viewContext
        )
        do {
            try viewContext.save()
            EntryLearningPipeline.processSavedEntry(
                text: trimmed,
                mood: selectedMood.rawValue,
                date: entry.date ?? Date(),
                duration: entry.duration
            )
            EntryLearningPipeline.upsertSemanticEntry(entry)
            JournalSpotlightIndexer.shared.upsert(entry: entry)
            DaypartHeroStore().recordPromptResponse(promptID: heroPromptID, wordCount: wordCount(for: trimmed))
            HapticManager.shared.entrySaved()
            cancelNewTextBlock()
            loadBlocks(backfill: false)
            return true
        } catch {
            viewContext.rollback()
            newTextBlockError = String(localized: "Couldn’t save. Try again.")
            return false
        }
    }

    func beginEditingBlock(_ item: JournalBlockTimelineItem) {
        if isComposingTextBlock {
            guard savePendingEditsBeforeExit() else { return }
        }
        editingBlockObjectID = item.id
        editingBlockText = item.text
        blockEditError = nil
        isTextFocused = true
        HapticManager.shared.selectionChanged()
    }

    @discardableResult
    private func finishEditingBlock(_ item: JournalBlockTimelineItem) -> Bool {
        guard let block = block(for: item) else { return false }
        guard JournalBlockTimelineStore.updateTextBlock(block, text: editingBlockText) else {
            blockEditError = String(localized: "Text can’t be empty. Delete it instead?")
            return false
        }
        do {
            try viewContext.save()
            EntryLearningPipeline.upsertSemanticEntry(entry)
            JournalSpotlightIndexer.shared.upsert(entry: entry)
            HapticManager.shared.entrySaved()
        } catch {
            viewContext.rollback()
            return false
        }
        isTextFocused = false
        editingBlockObjectID = nil
        editingBlockText = ""
        blockEditError = nil
        loadBlocks(backfill: false)
        return true
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

    private func entryTimestampNow(clock: Date = Date()) -> Date {
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
