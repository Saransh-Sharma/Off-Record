//
//  EntryDetailView.swift
//  OffRecord
//
//  Detail view for viewing and editing a single diary entry.
//  Supports text editing, mood selection, and audio playback.
//

import SwiftUI
import AVFoundation
import PhotosUI

private enum EntryDetailDateFormatters {
    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    static let fullDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        return formatter
    }()

    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

/// Detail view for a single diary entry.
/// Allows viewing, editing text, setting mood, playing back audio, and attaching photos.
struct EntryDetailView: View {
    @ObservedObject var entry: DiaryEntry
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @FocusState private var isTextFocused: Bool

    @State private var text: String
    @State private var selectedMood: Mood
    @State private var showMoodPicker = false
    @State private var isEditing = false
    @State private var showAIInsights = false
    @State private var aiAnalysis: AIAnalysisResult?
    private let deleteEmptyDraftOnDisappear: Bool
    private let promptContext: String?
    private let heroPromptID: String?
    @State private var currentActivity: NSUserActivity?

    // Photo state
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var photoAttachments: [PhotoAttachment] = []
    #if canImport(UIKit)
    @State private var photoImages: [UIImage] = []
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
        _isEditing = State(initialValue: startEditing)
        let moodString = entry.value(forKey: "mood") as? String ?? ""
        _selectedMood = State(initialValue: Mood(rawValue: moodString) ?? .none)
    }

    var body: some View {
        ZStack {
            OffRecordColor.appBackgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    // Header card with metadata
                    headerCard
                        .padding(.horizontal)
                        .padding(.top, 8)

                    // Audio player (when audio exists locally)
                    if hasAudio, let url = audioURL() {
                        AudioPlayerView(audioURL: url)
                            .padding(.horizontal)
                            .padding(.top, 4)
                    }

                    // Photo section
                    photoSection
                        .padding(.horizontal)
                        .padding(.top, 4)

                    // Main content area
                    if isEditing {
                        editingView
                    } else {
                        readingView

                        if !text.isEmpty {
                            aiInsightsSection
                        }
                    }
                }
            }
            .frame(maxWidth: isIPad ? 700 : .infinity)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(formattedShortDate)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    Button(action: toggleStar) {
                        Image(systemName: entry.isStarred ? "star.fill" : "star")
                            .foregroundColor(entry.isStarred ? OffRecordColor.textYellow : OffRecordColor.textSecondary)
                    }

                    Button(action: { isEditing.toggle() }) {
                        Text(isEditing ? "Done" : "Edit")
                    }
                }
            }
        }
        .onDisappear {
            saveIfNeeded()
            deleteEmptyDraftIfNeeded()
            currentActivity?.resignCurrent()
            currentActivity = nil
        }
        .onAppear {
            loadPhotos()
            startEntryActivity()
        }
        .onChange(of: selectedPhotos) { _, newItems in
            handlePhotoSelection(newItems)
        }
        .onChange(of: entry.text) { _, newValue in
            // Update local text when entry.text changes (e.g., after transcription completes)
            // Only update if not currently editing to avoid overwriting user edits
            if !isEditing && !isTextFocused {
                text = newValue ?? ""
            }
        }
        .fullScreenCover(isPresented: $showMoodPicker) {
            MoodDialSheet(selectedMood: $selectedMood, onSave: saveMood)
        }
    }

    // MARK: - Header Card

    private var headerCard: some View {
        VStack(spacing: 12) {
            // Date and time
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(formattedFullDate)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(OffRecordColor.textPrimary)
                    if let updatedAt = entry.updatedAt {
                        Text("Updated \(formattedTime(updatedAt))")
                            .font(.caption)
                            .foregroundColor(OffRecordColor.textSecondary)
                    }
                }
                Spacer()

                // Mood badge
                Button(action: { showMoodPicker = true }) {
                    if selectedMood == .none {
                        Label("Add mood", systemImage: "plus.circle")
                            .font(.caption)
                            .foregroundColor(OffRecordReadableTintStyle.journal.foreground)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
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
                                .font(.caption)
                        }
                        .foregroundColor(selectedMood.readableStyle.foreground)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
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

            // Stats row
            HStack(spacing: 20) {
                Label("\(wordCount) words", systemImage: "text.word.spacing")
                    .font(.caption)
                    .foregroundColor(OffRecordColor.textSecondary)

                if let duration = entry.value(forKey: "duration") as? Double, duration > 0 {
                    Label(formattedDuration(duration), systemImage: "waveform")
                        .font(.caption)
                        .foregroundColor(OffRecordColor.textSecondary)
                }

                Spacer()

                // Audio playback or "on other device" note
                if audioOnOtherDevice {
                    // Audio exists but on another device
                        HStack(spacing: 4) {
                            Image(systemName: "icloud")
                                .font(.caption)
                            Text("Audio on original device")
                                .font(.caption)
                        }
                        .foregroundColor(OffRecordColor.textSecondary)
                }
            }
        }
        .padding()
        .offRecordContentCard(cornerRadius: 12)
    }

    // MARK: - Reading View

    private var isTranscribing: Bool {
        text.isEmpty && hasAudioReference
    }

    private var readingView: some View {
        VStack(alignment: .leading, spacing: 0) {
            if text.isEmpty {
                if isTranscribing {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Transcribing your recording...")
                            .font(.subheadline)
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
                            .font(.subheadline)
                            .foregroundColor(OffRecordColor.textSecondary)
                    Button("Add text") {
                        isEditing = true
                    }
                    .font(.subheadline.weight(.medium))
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
                    .font(.body)
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
                isEditing = true
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
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(OffRecordColor.textHeading)
                    Spacer()
                    Image(systemName: showAIInsights ? "chevron.up" : "chevron.down")
                        .font(.caption)
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
                                .font(.caption)
                                .foregroundColor(OffRecordColor.textSecondary)
                        }
                        .frame(width: 70)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Sentiment")
                                .font(.caption)
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
                                .font(.caption)
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
                                .font(.caption)
                                .foregroundColor(OffRecordColor.textSecondary)
                            Text(analysis.intent.description)
                                .font(.subheadline)
                                .foregroundColor(OffRecordColor.textPrimary)
                        }
                    }
                    
                    // Topics
                    if !analysis.topics.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Topics")
                                .font(.caption)
                                .foregroundColor(OffRecordColor.textSecondary)
                            
                            FlowLayout(spacing: 6) {
                                ForEach(analysis.topics.prefix(5), id: \.self) { topic in
                                    Text(topic)
                                        .font(.caption)
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
                                .font(.caption)
                            Text("Reflection")
                                .font(.caption)
                        }
                        .foregroundColor(OffRecordColor.textSecondary)
                        Text(analysis.suggestedResponse)
                            .font(.caption)
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
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(OffRecordColor.textLavender)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Writing prompt")
                            .font(OffRecordTypography.labelSmall)
                            .foregroundStyle(OffRecordColor.textPeach)
                        Text(promptContext)
                            .font(.subheadline)
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

            TextEditor(text: $text)
                .font(.body)
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
                        .font(.caption)
                        .foregroundColor(OffRecordColor.textSecondary)

                    Spacer()

                    Button("Done") {
                        isTextFocused = false
                        isEditing = false
                    }
                    .font(.subheadline.weight(.medium))
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
                        .font(.caption)
                    Text(photoAttachments.isEmpty ? "Add Photos" : "Add More")
                        .font(.caption.weight(.medium))
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
                    .font(.caption)
                    .foregroundColor(OffRecordColor.textSecondary)
            }
        }
    }

    private func loadPhotos() {
        if PhotoStorageManager.shared.migrateLegacyPhotos(for: entry, in: viewContext) {
            try? viewContext.save()
        }
        photoAttachments = PhotoStorageManager.shared.attachments(for: entry)
        #if canImport(UIKit)
        photoImages = PhotoStorageManager.shared.images(for: entry)
        #endif
    }

    private func handlePhotoSelection(_ items: [PhotosPickerItem]) {
        #if canImport(UIKit)
        for item in items {
            let token = PerformanceSignposts.begin("PhotoImport")
            item.loadTransferable(type: Data.self) { result in
                guard case .success(let data) = result, let data else {
                    PerformanceSignposts.end(token)
                    return
                }

                Task { @MainActor in
                    guard let jpegData = await PhotoAttachmentProcessor.shared.preparedJPEGData(from: data),
                          let image = UIImage(data: jpegData) else {
                        PerformanceSignposts.end(token)
                        return
                    }

                    if let attachment = PhotoStorageManager.shared.addPhotoData(jpegData, to: entry, in: viewContext) {
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
        JournalSpotlightIndexer.shared.upsert(entry: entry)
    }

    // MARK: - Computed Properties

    private var wordCount: Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }

    private var characterCount: Int {
        text.count
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
        (entry.value(forKey: "audioFileName") as? String)?.isEmpty == false
    }

    /// Audio file exists locally on this device
    private var hasAudio: Bool {
        guard let url = audioURL() else { return false }
        return FileManager.default.fileExists(atPath: url.path)
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
        guard let fileName = entry.value(forKey: "audioFileName") as? String, !fileName.isEmpty else { return nil }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let recordingsDir = base.appendingPathComponent("Recordings", isDirectory: true)
        return recordingsDir.appendingPathComponent(fileName)
    }

    // MARK: - Actions

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

    private func saveIfNeeded() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentMood = entry.value(forKey: "mood") as? String ?? ""
        let oldText = entry.text ?? ""
        let needsSave = trimmed != oldText || selectedMood.rawValue != currentMood

        if needsSave {
            entry.text = trimmed
            entry.setValue(selectedMood.rawValue, forKey: "mood")
            entry.updatedAt = Date()
            do {
                try viewContext.save()
                EntryLearningPipeline.upsertSemanticEntry(entry)
                JournalSpotlightIndexer.shared.upsert(entry: entry)

                // Feed into Friday — use reprocess if text was edited
                if !trimmed.isEmpty {
                    DaypartHeroStore().recordPromptResponse(
                        promptID: heroPromptID,
                        wordCount: wordCount
                    )

                    if !oldText.isEmpty && trimmed != oldText {
                        EntryLearningPipeline.reprocessEditedEntry(
                            oldText: oldText,
                            newText: trimmed,
                            mood: selectedMood.rawValue,
                            date: entry.date ?? Date(),
                            duration: entry.duration
                        )
                    } else {
                        EntryLearningPipeline.processSavedEntry(
                            text: trimmed,
                            mood: selectedMood.rawValue,
                            date: entry.date ?? Date(),
                            duration: entry.duration
                        )
                    }
                }
            } catch {
                // ignore
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
        let hasSelectedMood = selectedMood != .none || entry.hasStartedEntryMood
        return trimmed.isEmpty
            && persistedText.isEmpty
            && !hasAudioReference
            && duration <= 0
            && photoCount == 0
            && !hasSelectedMood
    }

    private func saveMood() {
        entry.setValue(selectedMood.rawValue, forKey: "mood")
        entry.updatedAt = Date()
        HapticManager.shared.moodSelected()
        do {
            try viewContext.save()
            EntryLearningPipeline.upsertSemanticEntry(entry)
            JournalSpotlightIndexer.shared.upsert(entry: entry)
        } catch {
            // ignore
        }
    }

    private func startEntryActivity() {
        currentActivity?.resignCurrent()
        currentActivity = JournalSpotlightIndexer.shared.activity(for: entry)
        currentActivity?.becomeCurrent()
    }
}
