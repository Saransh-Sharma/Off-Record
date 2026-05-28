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
import PhotosUI
import os.log

private let entryDetailLogger = Logger(subsystem: "com.singularity.offrecord", category: "EntryDetail")

private enum EntryDetailDateFormatters {
    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateFormat = DateFormatter.dateFormat(
            fromTemplate: "MMM d",
            options: 0,
            locale: formatter.locale
        )
        return formatter
    }()

    static let fullDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateFormat = DateFormatter.dateFormat(
            fromTemplate: "EEEE MMMM d yyyy",
            options: 0,
            locale: formatter.locale
        )
        return formatter
    }()

    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

struct EntryDetailSaveDecision: Equatable {
    let shouldSave: Bool
    let shouldSaveText: Bool
    let skippedStaleTextOverwrite: Bool

    static func evaluate(
        localText: String,
        persistedText: String,
        hasEditedText: Bool,
        moodChanged: Bool
    ) -> EntryDetailSaveDecision {
        let trimmedLocalText = localText.trimmingCharacters(in: .whitespacesAndNewlines)
        let persistedHasText = !persistedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let textChanged = trimmedLocalText != persistedText
        let skippedStaleTextOverwrite = !hasEditedText && textChanged && persistedHasText

        return EntryDetailSaveDecision(
            shouldSave: (hasEditedText && textChanged) || moodChanged,
            shouldSaveText: hasEditedText && textChanged,
            skippedStaleTextOverwrite: skippedStaleTextOverwrite
        )
    }
}

private struct JournalBlockTimelineItem: Identifiable {
    let id: NSManagedObjectID
    let blockID: UUID
    let kind: JournalBlockKind
    let createdAt: Date
    let timestamp: String
    let text: String
    let mood: Mood
    let duration: TimeInterval
    let audioURL: URL?
    let audioExists: Bool
    let photoAttachmentID: UUID?

    var accessibilityLabel: String {
        switch kind {
        case .text:
            return "Text entry, \(timestamp)"
        case .audio:
            let seconds = Int(duration.rounded())
            return "Audio recording, \(seconds) seconds, \(timestamp)"
        case .mood:
            return "Mood check-in, \(mood.displayName), \(timestamp)"
        case .photo:
            return "Photo, \(timestamp)"
        }
    }
}

/// Detail view for a single diary entry.
/// Allows viewing, editing text, setting mood, playing back audio, and attaching photos.
struct EntryDetailView: View {
    @ObservedObject var entry: DiaryEntry
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isTextFocused: Bool

    @State private var text: String
    @State private var selectedMood: Mood
    @State private var showMoodPicker = false
    @State private var hasEditedText = false
    @State private var showAIInsights = false
    @State private var aiAnalysis: AIAnalysisResult?
    @State private var journalBlocks: [JournalBlock] = []
    @State private var timelineItems: [JournalBlockTimelineItem] = []
    @State private var editingBlockObjectID: NSManagedObjectID?
    @State private var editingBlockText = ""
    @State private var blockEditError: String?
    @State private var isComposingTextBlock = false
    @State private var newTextBlockText = ""
    @State private var newTextBlockError: String?
    @State private var showDeleteDayConfirm = false
    @State private var isDeletingDay = false
    private let deleteEmptyDraftOnDisappear: Bool
    private let promptContext: String?
    private let heroPromptID: String?
    @State private var currentActivity: NSUserActivity?

    // Photo state
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var photoAttachments: [PhotoAttachment] = []
    @State private var photoAttachmentByID: [UUID: PhotoAttachment] = [:]
    #if canImport(UIKit)
    @State private var photoImages: [UIImage] = []
    @State private var photoThumbnailByID: [UUID: UIImage] = [:]
    #endif

    private var isIPad: Bool { horizontalSizeClass == .regular }

    init(
        entry: DiaryEntry,
        startEditing: Bool = false,
        deleteEmptyDraftOnDisappear: Bool = false,
        promptContext: String? = nil,
        heroPromptID: String? = nil
    ) {
        self.entry = entry
        self.deleteEmptyDraftOnDisappear = deleteEmptyDraftOnDisappear
        self.promptContext = promptContext
        self.heroPromptID = heroPromptID
        _text = State(initialValue: entry.text ?? "")
        _isComposingTextBlock = State(initialValue: startEditing)
        let moodString = entry.value(forKey: "mood") as? String ?? ""
        _selectedMood = State(initialValue: Mood(rawValue: moodString) ?? .none)
    }

    var body: some View {
        ZStack {
            OffRecordColor.appBackgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    entryHeader
                        .padding(.horizontal)
                        .padding(.top, 8)

                    if isComposingTextBlock {
                        newTextBlockComposer
                    }

                    journalTimelineView

                    photoSection
                        .padding(.horizontal)
                        .padding(.vertical, 8)

                    if !text.isEmpty {
                        aiInsightsSection
                    }
                }
                .padding(.bottom, isActivelyEditing ? 160 : 96)
            }
            .scrollDismissesKeyboard(.interactively)
            .frame(maxWidth: isIPad ? 700 : .infinity)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(formattedShortDate)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if isActivelyEditing {
                    editorToolbarButton(
                        title: "Cancel",
                        systemImage: "xmark.circle.fill",
                        tint: OffRecordColor.textCoral,
                        fill: OffRecordColor.surfaceBlush,
                        border: OffRecordColor.brandCoral.opacity(0.22),
                        action: cancelActiveEditing
                    )

                    editorToolbarButton(
                        title: "Save",
                        systemImage: "checkmark.circle.fill",
                        tint: OffRecordColor.brandSageDark,
                        fill: OffRecordColor.surfaceSage,
                        border: OffRecordColor.borderSage,
                        action: saveActiveEditing
                    )
                    .disabled(!canSaveActiveEditing)
                    .opacity(canSaveActiveEditing ? 1 : 0.46)
                } else {
                    HStack(spacing: 16) {
                        Button(action: toggleStar) {
                            Image(systemName: entry.isStarred ? "star.fill" : "star")
                                .foregroundColor(entry.isStarred ? OffRecordColor.textYellow : OffRecordColor.textSecondary)
                        }

                        Menu {
                            Button(role: .destructive) {
                                showDeleteDayConfirm = true
                            } label: {
                                Label("Delete Day", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
        }
        .confirmationDialog(
            "Delete this day?",
            isPresented: $showDeleteDayConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Day", role: .destructive) {
                deleteWholeDay()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes all text, audio, moods, and photos for this date.")
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
        }
        .onAppear {
            loadPhotos()
            loadBlocks(backfill: true)
            startEntryActivity()
            syncTextFromEntry(reason: "appear")
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
        }
        .onChange(of: entry.entryTranscriptionStatus) { _, _ in
            syncTextFromEntry(reason: "transcriptionStatusChanged")
        }
        .fullScreenCover(isPresented: $showMoodPicker) {
            MoodDialSheet(selectedMood: $selectedMood, onSave: saveMood)
        }
    }

    // MARK: - Entry Header

    private var entryHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(formattedFullDate)
                        .font(OffRecordTypography.labelLarge)
                        .foregroundStyle(OffRecordColor.textHeading)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    if let updatedAt = entry.updatedAt {
                        Text("Updated \(formattedTime(updatedAt))")
                            .font(OffRecordTypography.metadata)
                            .foregroundStyle(OffRecordColor.textSecondary)
                    }
                }
                .layoutPriority(1)

                moodHeaderButton
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    metadataChip(
                        systemImage: "text.word.spacing",
                        text: "\(activeWordCount) words"
                    )

                    if let duration = entry.value(forKey: "duration") as? Double, duration > 0 {
                        metadataChip(systemImage: "waveform", text: formattedDuration(duration))
                    }

                    if !photoAttachments.isEmpty {
                        metadataChip(
                            systemImage: "photo",
                            text: "\(photoAttachments.count) \(photoAttachments.count == 1 ? "photo" : "photos")"
                        )
                    }

                    if audioOnOtherDevice {
                        metadataChip(systemImage: "icloud", text: "Audio on original device")
                    }
                }
                .padding(.vertical, 1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .offRecordClearGlassSurface(
            in: RoundedRectangle(cornerRadius: 20, style: .continuous),
            fallbackFill: OffRecordColor.surfaceWarm,
            clearFill: OffRecordColor.surfacePrimary.opacity(0.24),
            stroke: OffRecordColor.borderWarm.opacity(0.72),
            shadowRadius: 14,
            shadowY: 6
        )
    }

    private var moodHeaderButton: some View {
        Button(action: { showMoodPicker = true }) {
            if selectedMood == .none {
                Label("Mood", systemImage: "plus.circle.fill")
                    .font(OffRecordTypography.labelSmall)
                    .foregroundColor(OffRecordReadableTintStyle.journal.foreground)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .offRecordGlassControl(
                        tint: OffRecordReadableTintStyle.journal.tint,
                        in: Capsule(),
                        fallbackFill: OffRecordReadableTintStyle.journal.fill,
                        border: OffRecordReadableTintStyle.journal.border
                    )
            } else {
                HStack(spacing: 6) {
                    MiniMoodIcon(mood: selectedMood, size: 16, opacity: 0.92)
                    Text(selectedMood.displayName)
                        .font(OffRecordTypography.labelSmall)
                }
                .foregroundColor(selectedMood.readableStyle.foreground)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .offRecordGlassControl(
                    tint: selectedMood.readableStyle.tint,
                    in: Capsule(),
                    fallbackFill: selectedMood.readableStyle.fill,
                    border: selectedMood.readableStyle.border
                )
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("entryDetail.moodButton")
    }

    private func metadataChip(systemImage: String, text: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(OffRecordTypography.metadata)
            .foregroundStyle(OffRecordColor.textSecondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(OffRecordColor.surfacePrimary.opacity(0.68), in: Capsule())
            .overlay(Capsule().stroke(OffRecordColor.borderSoft, lineWidth: 1))
    }

    // MARK: - Reading View

    private var isTranscribing: Bool {
        entry.shouldShowTranscriptionSpinner(displayText: text)
    }

    private var journalTimelineView: some View {
        VStack(alignment: .leading, spacing: 12) {
            if timelineItems.isEmpty {
                if isTranscribing {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Transcribing your recording...")
                            .font(OffRecordTypography.bodySmall)
                            .foregroundColor(OffRecordColor.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                    .offRecordContentCard(cornerRadius: 12)
                } else {
                    if !isComposingTextBlock {
                        inlineAddTextPrompt
                    }
                }
            } else {
                ForEach(timelineItems) { item in
                    journalBlockRow(item)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                        .contextMenu {
                            if item.kind == .text {
                                Button {
                                    beginEditingBlock(item)
                                } label: {
                                    Label("Edit Block", systemImage: "pencil")
                                }
                            }
                            Button(role: .destructive) {
                                deleteBlock(item)
                            } label: {
                                Label("Delete Block", systemImage: "trash")
                            }
                        }
                }

                addTextButton
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .animation(reduceMotion ? .easeOut(duration: 0.01) : .easeOut(duration: 0.22), value: timelineItems.map(\.id))
    }

    private var inlineAddTextPrompt: some View {
        HStack {
            addTextButton
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private var addTextButton: some View {
        Button {
            beginNewTextBlock()
        } label: {
            Label("Add text", systemImage: "square.and.pencil")
        }
        .font(OffRecordTypography.labelMedium)
        .foregroundColor(OffRecordReadableTintStyle.brand.foreground)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .offRecordGlassControl(
            tint: OffRecordReadableTintStyle.brand.tint,
            in: Capsule(),
            fallbackFill: OffRecordReadableTintStyle.brand.fill,
            border: OffRecordReadableTintStyle.brand.border
        )
    }

    @ViewBuilder
    private func journalBlockRow(_ item: JournalBlockTimelineItem) -> some View {
        switch item.kind {
        case .text:
            textBlockRow(item)
        case .audio:
            audioBlockRow(item)
        case .mood:
            moodBlockRow(item)
        case .photo:
            photoBlockRow(item)
        }
    }

    private func textBlockRow(_ item: JournalBlockTimelineItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            blockHeader(item: item, systemImage: "text.alignleft", canEdit: true)

            if editingBlockObjectID == item.id {
                TextEditor(text: $editingBlockText)
                    .font(OffRecordTypography.journalBody)
                    .foregroundColor(OffRecordColor.textPrimary)
                    .lineSpacing(6)
                    .focused($isTextFocused)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 220)
                    .padding(14)
                    .background(OffRecordColor.surfaceWarm, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(blockEditError == nil ? OffRecordColor.borderWarm : OffRecordColor.brandCoral.opacity(0.42), lineWidth: 1)
                    )

                if let blockEditError {
                    Text(blockEditError)
                        .font(OffRecordTypography.metadata)
                        .foregroundColor(OffRecordColor.brandCoral)
                }
            } else {
                Text(item.text)
                    .font(OffRecordTypography.journalBody)
                    .foregroundColor(OffRecordColor.textPrimary)
                    .lineSpacing(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .onTapGesture {
                        beginEditingBlock(item)
                    }
            }
        }
        .padding(14)
        .background(OffRecordColor.surfacePrimary.opacity(0.84), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(OffRecordColor.borderSoft, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.accessibilityLabel)
    }

    private func audioBlockRow(_ item: JournalBlockTimelineItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            blockHeader(item: item, systemImage: "waveform", accent: OffRecordColor.textSky)
            if let url = item.audioURL, item.audioExists {
                AudioPlayerView(audioURL: url)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "icloud")
                    Text("Audio on original device")
                }
                .font(OffRecordTypography.metadata)
                .foregroundColor(OffRecordColor.textSecondary)
            }
        }
        .padding(14)
        .offRecordContentCard(cornerRadius: 18, fill: OffRecordColor.surfaceBlue)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.accessibilityLabel)
    }

    private func moodBlockRow(_ item: JournalBlockTimelineItem) -> some View {
        HStack(spacing: 12) {
            MiniMoodIcon(mood: item.mood, size: 26, opacity: 0.94)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.timestamp)
                    .font(OffRecordTypography.metadata)
                    .foregroundColor(OffRecordColor.textSecondary)
                Text(item.mood.displayName)
                    .font(OffRecordTypography.labelMedium)
                    .foregroundColor(OffRecordColor.textPrimary)
            }
            Spacer()
            blockOverflowMenu(item, canEdit: false)
        }
        .padding(14)
        .offRecordContentCard(cornerRadius: 18, fill: item.mood.readableStyle.fill)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.accessibilityLabel)
    }

    @ViewBuilder
    private func photoBlockRow(_ item: JournalBlockTimelineItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            blockHeader(item: item, systemImage: "photo", accent: OffRecordColor.textPeach)
            #if canImport(UIKit)
            if let id = item.photoAttachmentID,
               let image = photoThumbnailByID[id] {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            #endif
        }
        .padding(14)
        .offRecordContentCard(cornerRadius: 18, fill: OffRecordColor.surfacePeach)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.accessibilityLabel)
    }

    private func blockHeader(
        item: JournalBlockTimelineItem,
        systemImage: String,
        canEdit: Bool = false,
        accent: Color = OffRecordColor.textSecondary
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(accent)
            Text(item.timestamp)
            Spacer()
            blockOverflowMenu(item, canEdit: canEdit)
        }
        .font(OffRecordTypography.metadata)
        .foregroundColor(OffRecordColor.textSecondary)
    }

    private func blockOverflowMenu(_ item: JournalBlockTimelineItem, canEdit: Bool) -> some View {
        Menu {
            if canEdit {
                Button {
                    beginEditingBlock(item)
                } label: {
                    Label("Edit Block", systemImage: "pencil")
                }
            }
            Button(role: .destructive) {
                deleteBlock(item)
            } label: {
                Label("Delete Block", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(OffRecordTypography.labelSmall)
                .foregroundColor(OffRecordColor.textSecondary)
        }
        .accessibilityLabel("Block actions")
    }

    private var newTextBlockComposer: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let promptContext, !promptContext.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(OffRecordTypography.labelMedium)
                        .foregroundStyle(OffRecordColor.textLavender)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Writing prompt")
                            .font(OffRecordTypography.labelSmall)
                            .foregroundStyle(OffRecordColor.textPeach)
                        Text(promptContext)
                            .font(OffRecordTypography.bodySmall)
                            .foregroundStyle(OffRecordColor.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }
                .padding(14)
                .offRecordContentCard(cornerRadius: 14, fill: OffRecordColor.surfaceLavender)
            }

            TextEditor(text: $newTextBlockText)
                .font(OffRecordTypography.journalBody)
                .foregroundColor(OffRecordColor.textPrimary)
                .lineSpacing(6)
                .focused($isTextFocused)
                .scrollContentBackground(.hidden)
                .frame(minHeight: isIPad ? 360 : 320)
                .padding(18)
                .background(OffRecordColor.surfaceWarm, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(newTextBlockError == nil ? OffRecordColor.borderWarm : OffRecordColor.brandCoral.opacity(0.42), lineWidth: 1)
                )
                .shadow(color: OffRecordShadow.cardColor, radius: 18, x: 0, y: 8)
                .accessibilityLabel("New text block")

            if let newTextBlockError {
                Text(newTextBlockError)
                    .font(OffRecordTypography.metadata)
                    .foregroundColor(OffRecordColor.brandCoral)
            }

            HStack(spacing: 8) {
                Text("\(newTextBlockText.split { $0.isWhitespace || $0.isNewline }.count) words")
                    .font(OffRecordTypography.metadata)
                    .foregroundColor(OffRecordColor.textSecondary)

                Spacer()

                Label("Private draft", systemImage: "lock.shield.fill")
                    .font(OffRecordTypography.metadata)
                    .foregroundStyle(OffRecordColor.textSage)
            }
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .onAppear {
            isTextFocused = true
        }
    }

    private var readingView: some View {
        VStack(alignment: .leading, spacing: 0) {
            if text.isEmpty {
                if isTranscribing {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Transcribing your recording...")
                            .font(OffRecordTypography.bodySmall)
                            .foregroundColor(OffRecordColor.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "text.cursor")
                            .font(.system(size: 32))
                            .foregroundColor(OffRecordColor.textTertiary)
                        Text("No text yet")
                            .font(OffRecordTypography.bodySmall)
                            .foregroundColor(OffRecordColor.textSecondary)
                    Button("Add text") {
                        beginNewTextBlock()
                    }
                    .font(OffRecordTypography.labelMedium)
                    .foregroundColor(OffRecordReadableTintStyle.brand.foreground)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .offRecordGlassControl(
                        tint: OffRecordReadableTintStyle.brand.tint,
                        in: Capsule(),
                        fallbackFill: OffRecordReadableTintStyle.brand.fill,
                        border: OffRecordReadableTintStyle.brand.border
                    )
                }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                }
            } else {
                Text(text)
                    .font(OffRecordTypography.journalBody)
                    .foregroundColor(OffRecordColor.textPrimary)
                    .lineSpacing(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .textSelection(.enabled)
                    .accessibilityIdentifier("entryDetail.mainText")
            }
        }
        .frame(maxWidth: .infinity)
        .offRecordContentCard(cornerRadius: 12)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .onTapGesture {
            if !isTranscribing {
                beginNewTextBlock()
            }
        }
    }

    // MARK: - AI Insights Section
    
    private var aiInsightsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: {
                withAnimation(.spring(response: 0.3)) {
                    showAIInsights.toggle()
                    if showAIInsights && aiAnalysis == nil {
                        aiAnalysis = LocalAIEngine.shared.analyze(text: text)
                    }
                }
            }) {
                HStack {
                    Image(systemName: "brain.head.profile")
                        .foregroundColor(OffRecordColor.textLavender)
                    Text("AI Insights")
                        .font(OffRecordTypography.labelMedium)
                        .foregroundColor(OffRecordColor.textHeading)
                    Spacer()
                    Image(systemName: showAIInsights ? "chevron.up" : "chevron.down")
                        .font(OffRecordTypography.metadata)
                        .foregroundColor(OffRecordColor.textSecondary)
                }
                .padding()
                .offRecordGlassControl(
                    tint: showAIInsights ? OffRecordColor.brandLavenderDark : nil,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            
            if showAIInsights, let analysis = aiAnalysis {
                VStack(alignment: .leading, spacing: 16) {
                    // Emotion & Sentiment
                    HStack(spacing: 16) {
                        VStack(spacing: 4) {
                            MiniMoodIcon(
                                mood: analysis.dominantEmotion.representativeMood,
                                size: 24,
                                opacity: 0.92
                            )
                            Text(analysis.dominantEmotion.rawValue.capitalized)
                                .font(OffRecordTypography.metadata)
                                .foregroundColor(OffRecordColor.textSecondary)
                        }
                        .frame(width: 70)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Sentiment")
                                .font(OffRecordTypography.metadata)
                                .foregroundColor(OffRecordColor.textSecondary)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(OffRecordColor.borderSoft)
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(analysis.sentiment > 0 ? OffRecordColor.brandMint : OffRecordColor.brandPeach)
                                        .frame(width: geo.size.width * CGFloat(abs(analysis.sentiment)))
                                }
                            }
                            .frame(height: 8)
                            
                            Text(analysis.sentiment > 0.2 ? "Positive" : (analysis.sentiment < -0.2 ? "Negative" : "Neutral"))
                                .font(OffRecordTypography.metadata)
                                .foregroundColor(OffRecordColor.textSecondary)
                        }
                    }
                    
                    Divider()
                    
                    // Intent
                    HStack {
                        Image(systemName: "quote.bubble")
                            .foregroundColor(OffRecordColor.textSky)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Intent")
                                .font(OffRecordTypography.metadata)
                                .foregroundColor(OffRecordColor.textSecondary)
                            Text(analysis.intent.description)
                                .font(OffRecordTypography.bodySmall)
                                .foregroundColor(OffRecordColor.textPrimary)
                        }
                    }
                    
                    // Topics
                    if !analysis.topics.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Topics")
                                .font(OffRecordTypography.metadata)
                                .foregroundColor(OffRecordColor.textSecondary)
                            
                            FlowLayout(spacing: 6) {
                                ForEach(analysis.topics.prefix(5), id: \.self) { topic in
                                    Text(topic)
                                        .font(OffRecordTypography.metadata)
                                        .foregroundColor(OffRecordColor.textLavender)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(OffRecordColor.backgroundLavenderTint)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                    
                    // AI Response
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "bubble.left.and.text.bubble.right")
                                .font(OffRecordTypography.metadata)
                            Text("Reflection")
                                .font(OffRecordTypography.metadata)
                        }
                        .foregroundColor(OffRecordColor.textSecondary)
                        Text(analysis.suggestedResponse)
                            .font(OffRecordTypography.metadata)
                            .foregroundColor(OffRecordColor.textPrimary)
                            .italic()
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(OffRecordColor.surfaceLavender)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding()
                .offRecordContentCard(cornerRadius: 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    // MARK: - Editing View

    private var editingView: some View {
        VStack(spacing: 0) {
            if let promptContext, !promptContext.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(OffRecordTypography.labelMedium)
                        .foregroundStyle(OffRecordColor.textLavender)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Writing prompt")
                            .font(OffRecordTypography.labelSmall)
                            .foregroundStyle(OffRecordColor.textPeach)
                        Text(promptContext)
                            .font(OffRecordTypography.bodySmall)
                            .foregroundStyle(OffRecordColor.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }
                .padding(14)
                .offRecordContentCard(cornerRadius: 14, fill: OffRecordColor.surfaceLavender)
                .padding(.horizontal)
                .padding(.top, 8)
            }

            TextEditor(text: editableTextBinding)
                .font(OffRecordTypography.journalBody)
                .foregroundColor(OffRecordColor.textPrimary)
                .lineSpacing(6)
                .focused($isTextFocused)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 300)
                .padding()
                .offRecordContentCard(cornerRadius: 12)
                .padding(.horizontal)
                .padding(.vertical, 8)

            // Keyboard toolbar
            if isTextFocused {
                HStack {
                    Text("\(wordCount) words · \(characterCount) chars")
                        .font(OffRecordTypography.metadata)
                        .foregroundColor(OffRecordColor.textSecondary)

                    Spacer()

                    Button("Done") {
                        saveNewTextBlock()
                    }
                    .font(OffRecordTypography.labelMedium)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .offRecordGlassBar(cornerRadius: 0, fallbackFill: OffRecordColor.surfaceWarm)
            }
        }
        .onAppear {
            isTextFocused = true
        }
    }

    // MARK: - Photo Section

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            #if canImport(UIKit)
            // Photo thumbnails
            if !photoImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(photoImages.enumerated()), id: \.offset) { index, image in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: isIPad ? 120 : 80, height: isIPad ? 120 : 80)
                                    .clipShape(RoundedRectangle(cornerRadius: isIPad ? 12 : 8))

                                Button {
                                    removePhoto(at: index)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundStyle(OffRecordColor.textInverse, OffRecordColor.brandCoral)
                                }
                                .offset(x: 6, y: -6)
                            }
                        }
                    }
                }
            }
            #endif

            // Photo picker
            PhotosPicker(
                selection: $selectedPhotos,
                maxSelectionCount: 5,
                matching: .images
            ) {
                HStack(spacing: 6) {
                    Image(systemName: "photo.badge.plus")
                        .font(OffRecordTypography.metadata)
                    Text(photoAttachments.isEmpty ? "Add Photos" : "Add More")
                        .font(OffRecordTypography.labelSmall)
                }
                .foregroundColor(OffRecordReadableTintStyle.journal.foreground)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .offRecordGlassControl(
                    tint: OffRecordReadableTintStyle.journal.tint,
                    in: Capsule(),
                    fallbackFill: OffRecordReadableTintStyle.journal.fill,
                    border: OffRecordReadableTintStyle.journal.border
                )
            }

            if !photoAttachments.isEmpty {
                Text("Photos sync with iCloud")
                    .font(OffRecordTypography.metadata)
                    .foregroundColor(OffRecordColor.textSecondary)
            }
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

    private func removePhoto(at index: Int) {
        guard index < photoAttachments.count else { return }
        let attachment = photoAttachments[index]
        PhotoStorageManager.shared.removePhoto(attachment, from: entry, in: viewContext)
        photoAttachments.remove(at: index)
        #if canImport(UIKit)
        if index < photoImages.count {
            photoImages.remove(at: index)
        }
        #endif
        savePhotos()
        HapticManager.shared.entryDeleted()
    }

    private func savePhotos() {
        entry.updatedAt = Date()
        try? viewContext.save()
        photoAttachments = PhotoStorageManager.shared.attachments(for: entry)
        loadBlocks(backfill: false)
        JournalSpotlightIndexer.shared.upsert(entry: entry)
    }

    // MARK: - Computed Properties

    private var isActivelyEditing: Bool {
        isComposingTextBlock || editingBlockObjectID != nil
    }

    private var activeEditingItem: JournalBlockTimelineItem? {
        guard let editingBlockObjectID else { return nil }
        return timelineItems.first { $0.id == editingBlockObjectID }
    }

    private var canSaveActiveEditing: Bool {
        if isComposingTextBlock {
            return !newTextBlockText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if editingBlockObjectID != nil {
            return !editingBlockText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return false
    }

    private var activeWordCount: Int {
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

    private func editorToolbarButton(
        title: String,
        systemImage: String,
        tint: Color,
        fill: Color,
        border: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label {
                Text(title)
                    .font(OffRecordTypography.labelSmall)
            } icon: {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(fill, in: Capsule())
            .overlay(Capsule().stroke(border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private var formattedShortDate: String {
        EntryDetailDateFormatters.shortDate.string(from: entry.date ?? Date())
    }

    private var formattedFullDate: String {
        EntryDetailDateFormatters.fullDate.string(from: entry.date ?? Date())
    }

    private func formattedTime(_ date: Date) -> String {
        EntryDetailDateFormatters.time.string(from: date)
    }

    /// Entry has an audio filename stored (may have been recorded on another device)
    private var hasAudioReference: Bool {
        !audioURLs().isEmpty
    }

    /// Audio file exists locally on this device
    private var hasAudio: Bool {
        audioURLs().contains { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Audio was recorded but file is on another device (synced via iCloud)
    private var audioOnOtherDevice: Bool {
        hasAudioReference && !hasAudio
    }

    private func formattedDuration(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }

    private func audioURL() -> URL? {
        audioURLs().first
    }

    private func audioURLs() -> [URL] {
        AudioAttachmentStore.audioURLs(for: entry)
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

    private func block(for item: JournalBlockTimelineItem) -> JournalBlock? {
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

    private func toggleStar() {
        entry.isStarred.toggle()
        entry.updatedAt = Date()
        HapticManager.shared.entryStarred()
        do {
            try viewContext.save()
            EntryLearningPipeline.upsertSemanticEntry(entry)
            JournalSpotlightIndexer.shared.upsert(entry: entry)
        } catch {
            // ignore
        }
    }

    private func toggleEditingMode() {
        if isComposingTextBlock {
            cancelNewTextBlock()
        } else {
            beginNewTextBlock()
        }
    }

    private func saveActiveEditing() {
        if isComposingTextBlock {
            _ = saveNewTextBlock()
        } else if let activeEditingItem {
            _ = finishEditingBlock(activeEditingItem)
        }
    }

    private func cancelActiveEditing() {
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
        if isComposingTextBlock {
            let trimmed = newTextBlockText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                cancelNewTextBlock()
                return true
            }
            return saveNewTextBlock()
        }

        if let activeEditingItem {
            let trimmed = editingBlockText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                cancelEditingBlock()
                return true
            }
            return finishEditingBlock(activeEditingItem)
        }

        return true
    }

    private func beginNewTextBlock() {
        newTextBlockText = ""
        newTextBlockError = nil
        isComposingTextBlock = true
        isTextFocused = true
        HapticManager.shared.selectionChanged()
    }

    private func cancelNewTextBlock() {
        isTextFocused = false
        isComposingTextBlock = false
        newTextBlockText = ""
        newTextBlockError = nil
    }

    @discardableResult
    private func saveNewTextBlock() -> Bool {
        let trimmed = newTextBlockText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            newTextBlockError = "Write something before saving this block."
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
            newTextBlockError = "Could not save this block. Please try again."
            return false
        }
    }

    private func beginEditingBlock(_ item: JournalBlockTimelineItem) {
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
            blockEditError = "Text blocks cannot be empty. Delete the block if you no longer need it."
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

    private func deleteBlock(_ item: JournalBlockTimelineItem) {
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
