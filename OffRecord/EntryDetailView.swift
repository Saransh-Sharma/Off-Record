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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState var isTextFocused: Bool

    @State var text: String
    @State var selectedMood: Mood
    @State var showMoodPicker = false
    @State private var hasEditedText = false
    @State private var showAIInsights = false
    @State private var aiAnalysis: EntryInsight?
    @State private var journalBlocks: [JournalBlock] = []
    @State private var timelineItems: [JournalBlockTimelineItem] = []
    @State var editingBlockObjectID: NSManagedObjectID?
    @State var editingBlockText = ""
    @State var blockEditError: String?
    @State private var isComposingTextBlock = false
    @State private var newTextBlockText = ""
    @State private var newTextBlockError: String?
    @State var showDeleteDayConfirm = false
    @State private var pendingBlockDeletion: JournalBlockTimelineItem?
    @State private var deeperQuestion: String?
    @State private var isFetchingDeeperQuestion = false
    @State private var composerPrompt: String?
    @State private var isDeletingDay = false
    @AppStorage(FridayAvailability.defaultsKey) private var isFridayEnabled = true
    private let deleteEmptyDraftOnDisappear: Bool
    private let promptContext: String?
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

    private var isIPad: Bool { horizontalSizeClass == .regular }
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

    // MARK: - Reading View

    private var isTranscribing: Bool {
        entry.shouldShowTranscriptionSpinner(displayText: text)
    }

    private var entryPresentationLayout: JournalEntryPresentationLayout {
        JournalEntryPresentationClassifier.layout(
            for: timelineItems.map(\.presentationBlock)
        )
    }

    private var journalTimelineView: some View {
        VStack(alignment: .leading, spacing: OffRecordSpacing.md) {
            if timelineItems.isEmpty {
                if isTranscribing {
                    VStack(spacing: OffRecordSpacing.md) {
                        Image(systemName: "waveform")
                            .font(OffRecordTypography.titleLarge)
                            .foregroundStyle(OffRecordColor.textLavender)
                            .symbolEffect(.variableColor.iterative, isActive: !reduceMotion)
                            .accessibilityHidden(true)
                        Text("Transcribing…")
                            .font(OffRecordTypography.bodySmall)
                            .foregroundColor(OffRecordColor.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, OffRecordSpacing.section)
                    .offRecordContentCard(cornerRadius: OffRecordRadius.lg)
                } else {
                    if !isComposingTextBlock {
                        emptyEntryPrompt
                    }
                }
            } else {
                switch entryPresentationLayout {
                case .singleEntry:
                    sectionLabel(dayName)
                    singleEntryCanvas
                case .multiEntry:
                    sectionLabel(dayName)
                    multiEntryTimeline
                }
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.01) : .easeOut(duration: 0.22), value: timelineItems.map(\.id))
    }

    /// "Today", "Yesterday", the weekday ("Wednesday") within a week, or the date ("Sep 12").
    private var dayName: String {
        let date = entry.date ?? Date()
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return String(localized: "Today") }
        if calendar.isDateInYesterday(date) { return String(localized: "Yesterday") }
        if let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: Date())).day, days < 7 {
            return date.formatted(.dateTime.weekday(.wide))
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
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

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(OffRecordTypography.labelSmall)
            .foregroundStyle(OffRecordColor.textSecondary)
            .textCase(.uppercase)
            .tracking(0.6)
            .padding(.horizontal, 2)
            .accessibilityAddTraits(.isHeader)
    }

    private var emptyEntryPrompt: some View {
        VStack(spacing: OffRecordSpacing.md) {
            OffRecordIconBubble(
                systemImage: "square.and.pencil",
                tint: OffRecordColor.textLavender,
                fill: OffRecordColor.surfaceLavender,
                size: 46,
                iconSize: 18
            )
            Text("Nothing Here Yet")
                .font(OffRecordTypography.labelMedium)
                .foregroundStyle(OffRecordColor.textHeading)
            Text("Add text, a photo, or a mood.")
                .font(OffRecordTypography.bodySmall)
                .foregroundStyle(OffRecordColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .background(OffRecordColor.surfaceWarm, in: RoundedRectangle(cornerRadius: OffRecordRadius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: OffRecordRadius.xl, style: .continuous)
                .stroke(OffRecordColor.borderSoft, lineWidth: 1)
        )
        .shadow(color: OffRecordShadow.cardColor, radius: 18, x: 0, y: 8)
    }

    private var singleEntryCanvas: some View {
        VStack(spacing: 0) {
            ForEach(Array(timelineItems.enumerated()), id: \.element.id) { index, item in
                singleEntryRow(item, isLast: index == timelineItems.count - 1)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                    .contextMenu { blockContextMenu(for: item) }
            }
        }
        .padding(14)
        .background(OffRecordColor.surfaceLavender.opacity(0.56), in: RoundedRectangle(cornerRadius: OffRecordRadius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: OffRecordRadius.xl, style: .continuous)
                .stroke(OffRecordColor.brandLavender.opacity(0.28), lineWidth: 1)
        )
        .shadow(color: OffRecordShadow.cardColor, radius: 18, x: 0, y: 8)
    }

    private var multiEntryTimeline: some View {
        LazyVStack(spacing: TimelineDesign.monthRowSpacing) {
            ForEach(Array(timelineItems.enumerated()), id: \.element.id) { index, item in
                HStack(alignment: .top, spacing: TimelineDesign.dayRowContentSpacing) {
                    dayTimelineNode(for: item, isLast: index == timelineItems.count - 1)
                        .frame(width: TimelineDesign.daySpineWidth)

                    journalBlockRow(item)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                        .contextMenu { blockContextMenu(for: item) }
                }
                .frame(minHeight: minHeight(for: item), alignment: .top)
            }
        }
    }

    /// How Friday may respond to this entry; high-risk text is never analyzed or asked about.
    private var entryResponseMode: SensitiveResponseMode {
        JournalRiskClassifier.responseMode(for: text)
    }

    private var entrySupportCard: some View {
        VStack(alignment: .leading, spacing: OffRecordSpacing.md) {
            Text(FridayPersonality.riskSafeSupport)
                .font(OffRecordTypography.bodyLarge)
                .foregroundStyle(OffRecordColor.textBrand)
                .fixedSize(horizontal: false, vertical: true)
            GetSupportButton()
        }
        .padding(OffRecordSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .offRecordCard(cornerRadius: OffRecordRadius.lg)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("entryDetail.support")
    }

    private var goDeeperCard: some View {
        VStack(alignment: .leading, spacing: OffRecordSpacing.md) {
            HStack(spacing: OffRecordSpacing.sm) {
                Image(systemName: "sparkles")
                    .foregroundStyle(OffRecordColor.textLavender)
                    .accessibilityHidden(true)
                Text("Go Deeper")
                    .font(OffRecordTypography.labelLarge)
                    .foregroundStyle(OffRecordColor.textHeading)
                Spacer(minLength: 0)
                Button(action: showDeeperQuestion) {
                    Group {
                        if isFetchingDeeperQuestion {
                            ProgressView()
                                .tint(OffRecordColor.textLavender)
                        } else {
                            Image(systemName: deeperQuestion == nil ? "questionmark.bubble" : "arrow.triangle.2.circlepath")
                                .font(OffRecordTypography.labelLarge)
                                .foregroundStyle(OffRecordColor.textLavender)
                                .contentTransition(.symbolEffect(.replace))
                        }
                    }
                    .frame(width: OffRecordLayout.minimumTapTarget, height: OffRecordLayout.minimumTapTarget)
                }
                .buttonStyle(.plain)
                .disabled(isFetchingDeeperQuestion)
                .accessibilityLabel(deeperQuestion == nil ? "Get a Question" : "Another Question")
                .accessibilityIdentifier("entryDetail.goDeeper")
            }

            if let deeperQuestion {
                Text(deeperQuestion)
                    .font(OffRecordTypography.bodyLarge)
                    .foregroundStyle(OffRecordColor.textBrand)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .id(deeperQuestion)

                HStack(spacing: OffRecordSpacing.sm) {
                    Button {
                        composerPrompt = deeperQuestion
                        beginNewTextBlock()
                    } label: {
                        Label(String(localized: "Write", comment: "Button that answers the question by writing."), systemImage: "square.and.pencil")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(OffRecordSoftButtonStyle(tint: OffRecordColor.textBrand, fill: OffRecordColor.surfacePrimary))

                    Button {
                        let capture = CaptureController.shared
                        if let date = entry.date { capture.captureDate = date }
                        capture.startRecording(prompt: deeperQuestion)
                    } label: {
                        Label(String(localized: "Record", comment: "Button that answers the question by recording audio."), systemImage: "mic.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(OffRecordSoftButtonStyle(tint: OffRecordColor.textOnAccent, fill: OffRecordColor.brandPlum))
                }
            } else {
                Text("I’ll ask one question about what you wrote.")
                    .font(OffRecordTypography.bodySmall)
                    .foregroundStyle(OffRecordColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(OffRecordSpacing.lg)
        .offRecordCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfaceLavender.opacity(0.7), shadow: false)
    }

    /// The first tap asks for the entry's question (the model's, when it passes
    /// validation); later taps cycle through the templates.
    private func showDeeperQuestion() {
        let provider = GoDeeperQuestionProvider.shared
        guard deeperQuestion != nil else {
            let entryText = text
            let mood = selectedMood
            let allowsModel = FridayEntryIntelligence.isEligible(entry)
            isFetchingDeeperQuestion = true
            Task { @MainActor in
                let question = await provider.firstQuestion(text: entryText, mood: mood, allowsModel: allowsModel)
                isFetchingDeeperQuestion = false
                withOffRecordAnimation(OffRecordMotion.gentle) {
                    deeperQuestion = question
                }
                HapticManager.shared.selectionChanged()
            }
            return
        }
        withOffRecordAnimation(OffRecordMotion.gentle) {
            deeperQuestion = provider.nextQuestion(text: text, mood: selectedMood, excluding: deeperQuestion) ?? deeperQuestion
        }
        HapticManager.shared.selectionChanged()
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

    private func singleEntryRow(_ item: JournalBlockTimelineItem, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: OffRecordSpacing.md) {
            ZStack(alignment: .top) {
                if !isLast {
                    TimelineSpineLine()
                        .stroke(OffRecordColor.brandLavender.opacity(0.44), style: StrokeStyle(lineWidth: 1))
                        .padding(.top, 44)
                        .frame(maxHeight: .infinity)
                }

                timelineIconBubble(for: item, size: 44)
            }
            .frame(width: 46)
            .frame(minHeight: minHeight(for: item))

            singleEntryBlockContent(item)
                .padding(.bottom, isLast ? 0 : OffRecordSpacing.md)
        }
    }

    private func singleEntryBlockContent(_ item: JournalBlockTimelineItem) -> some View {
        VStack(alignment: .leading, spacing: OffRecordSpacing.sm) {
            blockHeader(item: item, systemImage: item.systemImage, canEdit: item.kind == .text, accent: item.accentColor)

            switch item.kind {
            case .text:
                textBlockBody(item)
            case .audio:
                audioBlockBody(item)
                    .padding(12)
                    .background(OffRecordColor.surfaceBlue, in: RoundedRectangle(cornerRadius: OffRecordRadius.lg, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: OffRecordRadius.lg, style: .continuous)
                            .stroke(OffRecordColor.brandSky.opacity(0.28), lineWidth: 1)
                    )
            case .mood:
                HStack(spacing: OffRecordSpacing.sm) {
                    if item.mood != .none {
                        item.mood.miniImage
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                            .accessibilityHidden(true)
                    }
                    Text(item.mood.displayName)
                        .font(OffRecordTypography.labelMedium)
                        .foregroundStyle(OffRecordColor.textPrimary)
                }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(item.mood.readableStyle.fill, in: RoundedRectangle(cornerRadius: OffRecordRadius.lg, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: OffRecordRadius.lg, style: .continuous)
                            .stroke(item.mood.readableStyle.border, lineWidth: 1)
                    )
            case .photo:
                photoBlockBody(item)
            }
        }
    }

    private func dayTimelineNode(for item: JournalBlockTimelineItem, isLast: Bool) -> some View {
        ZStack(alignment: .top) {
            if !isLast {
                TimelineSpineLine()
                    .stroke(
                        OffRecordColor.textTertiary.opacity(0.58),
                        style: StrokeStyle(lineWidth: 0.95, dash: [4, 7], dashPhase: 1)
                    )
                    .padding(.top, 52)
                    .frame(maxHeight: .infinity)
                    .allowsHitTesting(false)
            }

            Text(item.timeText)
                .font(OffRecordTypography.badgeLabel)
                .foregroundStyle(item.nodeForeground)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .frame(width: 50, height: 50)
                .background(Circle().fill(item.nodeFill))
                .overlay(Circle().stroke(item.nodeBorder, lineWidth: 1.1))
                .accessibilityLabel("\(item.timeText), \(item.accessibilityLabel)")
        }
        .frame(minHeight: minHeight(for: item))
    }

    private func timelineIconBubble(for item: JournalBlockTimelineItem, size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(item.nodeFill)
                .overlay(Circle().stroke(item.nodeBorder, lineWidth: 1))
            Image(systemName: item.systemImage)
                .font(size == 44 ? OffRecordTypography.labelLarge : OffRecordTypography.labelMedium)
                .foregroundStyle(item.nodeForeground)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func blockContextMenu(for item: JournalBlockTimelineItem) -> some View {
        if item.kind == .text {
            Button {
                beginEditingBlock(item)
            } label: {
                Label(String(localized: "Edit", comment: "Menu action that edits a text block."), systemImage: "pencil")
            }
        }
        if item.kind == .text, let text = block(for: item)?.textValue, !text.isEmpty {
            Button {
                UIPasteboard.general.string = text
            } label: {
                Label("Copy Text", systemImage: "doc.on.doc")
            }
        }
        Button(role: .destructive) {
            pendingBlockDeletion = item
        } label: {
            Label(String(localized: "Delete", comment: "Menu action that deletes a block from the entry."), systemImage: "trash")
        }
    }

    private func minHeight(for item: JournalBlockTimelineItem) -> CGFloat {
        switch item.kind {
        case .text:
            return max(TimelineDesign.entryRowMinHeight, editingBlockObjectID == item.id ? 300 : 112)
        case .audio:
            return 132
        case .mood:
            return 82
        case .photo:
            return 150
        }
    }

    private var newTextBlockComposer: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let promptContext = composerPrompt ?? promptContext, !promptContext.isEmpty {
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
                .accessibilityLabel("New text")
                .accessibilityIdentifier("entryDetail.newTextBlock")

            if let newTextBlockError {
                Text(newTextBlockError)
                    .font(OffRecordTypography.metadata)
                    .foregroundColor(OffRecordColor.brandCoral)
            }

            HStack(spacing: 8) {
                Text("^[\(newTextBlockText.split { $0.isWhitespace || $0.isNewline }.count) word](inflect: true)")
                    .font(OffRecordTypography.metadata)
                    .foregroundColor(OffRecordColor.textSecondary)

                Spacer()
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 8)
        .onAppear {
            isTextFocused = true
        }
    }

    // MARK: - AI Insights Section
    
    private var aiInsightsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: {
                withOffRecordAnimation(OffRecordMotion.snappy) {
                    showAIInsights.toggle()
                    if showAIInsights {
                        // Read fresh each time it opens, so an edit never shows stale notes.
                        aiAnalysis = EntryInsightAnalyzer.analyze(
                            text: text,
                            responseMode: entryResponseMode,
                            recurringTopic: recurringTopicName(for:)
                        )
                    }
                }
            }) {
                HStack(spacing: OffRecordSpacing.md) {
                    OffRecordIconBubble(
                        systemImage: "sparkles",
                        tint: OffRecordColor.textLavender,
                        fill: OffRecordColor.surfaceLavender,
                        size: 44,
                        iconSize: 17
                    )

                    VStack(alignment: .leading, spacing: 3) {
                        Text("From Friday", comment: "Header for the assistant’s notes on this entry. Friday is the assistant’s name, not the weekday.")
                            .font(OffRecordTypography.labelMedium)
                            .foregroundColor(OffRecordColor.textHeading)
                    }
                    .layoutPriority(1)

                    Image(systemName: showAIInsights ? "chevron.down" : "chevron.right")
                        .font(OffRecordTypography.metadata)
                        .foregroundColor(OffRecordColor.textSecondary)
                }
                .padding(18)
                .background(OffRecordColor.surfacePrimary, in: RoundedRectangle(cornerRadius: OffRecordRadius.xl, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: OffRecordRadius.xl, style: .continuous)
                        .stroke(OffRecordColor.borderSoft, lineWidth: 1)
                )
                .shadow(color: OffRecordShadow.cardColor, radius: 18, x: 0, y: 8)
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
                            Text(analysis.dominantEmotion.representativeMood.displayName)
                                .font(OffRecordTypography.metadata)
                                .foregroundColor(OffRecordColor.textSecondary)
                        }
                        .frame(width: 70)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Tone")
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
                            .accessibilityElement()
                            .accessibilityLabel("Tone")
                            .accessibilityValue(toneLabel(for: analysis.sentiment))

                            Text(toneLabel(for: analysis.sentiment))
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
                            Text("About")
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
                            Text("Friday", comment: "Name of the in-app assistant, not the weekday.")
                                .font(OffRecordTypography.metadata)
                        }
                        .foregroundColor(OffRecordColor.textSecondary)
                        Text(analysis.fridayLine)
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
                .offRecordContentCard(cornerRadius: OffRecordRadius.xl, fill: OffRecordColor.surfaceWarm)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.bottom, 8)
    }

    /// The name Friday uses for `topic` when it comes up often, honoring Forget and Rename.
    private func recurringTopicName(for topic: String) -> String? {
        guard let node = FridayAssistantEngine.shared.knowledgeGraph.nodes[topic.lowercased()],
              node.type == .topic || node.type == .place,
              node.mentions > 3 else { return nil }
        let preferences = FridayMemoryPreferences.shared
        guard !preferences.isForgotten(node) else { return nil }
        return preferences.displayName(for: node)
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

    private func toneLabel(for sentiment: Double) -> String {
        if sentiment > 0.2 {
            return String(localized: "Light", comment: "Tone of an entry: mostly positive.")
        }
        if sentiment < -0.2 {
            return String(localized: "Heavy", comment: "Tone of an entry: mostly negative.")
        }
        return String(localized: "Neutral", comment: "Tone of an entry: neither positive nor negative.")
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

    private func beginNewTextBlock() {
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
