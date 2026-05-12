//
//  TodayView.swift
//  OffRecord
//
//  Main recording interface for creating voice diary entries.
//  Handles audio recording, transcription, and entry creation.
//

import SwiftUI
import CoreData
import AVFoundation
import UIKit
import PhotosUI
import os.log

private let logger = Logger(subsystem: "com.singularity.offrecord", category: "TodayView")

// MARK: - Recording State

/// Represents the current state of the recording process
enum RecordingState {
    case idle       // Ready to record
    case recording  // Currently recording audio
    case processing // Transcribing audio to text
}

// MARK: - Today View

/// Main view for recording and viewing today's diary entry.
/// Provides voice recording with real-time audio level visualization.
struct TodayView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage("authorName") private var authorName: String = ""
    @ObservedObject private var proactiveReflection = ProactiveReflectionController.shared
    private let compactTabSelection: Binding<OffRecordTab>?

    @StateObject private var recorder = AudioRecorder()
    @State private var recordingState: RecordingState = .idle
    @State private var errorMessage: String?
    @State private var selectedPrompt: EntryPrompt? = nil
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var noteEntry: DiaryEntry?
    @State private var isShowingNoteEditor = false
    @State private var shouldDeleteEmptyNoteDraft = false
    @State private var notePromptContext: String?
    @State private var noteHeroPromptID: String?
    @State private var selectedHero: SelectedDaypartHero?
    @State private var heroStore = DaypartHeroStore()
    @State private var activeHeroPromptID: String?
    @State private var heroRecordingPromptID: String?

    @FetchRequest private var todayEntries: FetchedResults<DiaryEntry>
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \DiaryEntry.date, ascending: true)],
        animation: .default)
    private var allEntries: FetchedResults<DiaryEntry>

    private var isIPad: Bool { horizontalSizeClass == .regular }

    init(compactTabSelection: Binding<OffRecordTab>? = nil) {
        self.compactTabSelection = compactTabSelection
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        _todayEntries = FetchRequest<DiaryEntry>(
            sortDescriptors: [NSSortDescriptor(keyPath: \DiaryEntry.date, ascending: false)],
            predicate: NSPredicate(format: "date >= %@ AND date < %@", startOfDay as NSDate, endOfDay as NSDate),
            animation: .default
        )
    }

    private var latestEntry: DiaryEntry? {
        todayEntries.first
    }

    private var effectiveLatestEntry: DiaryEntry? {
        if isHeroUITestEmptyToday || isHeroUITestFirstRun {
            return nil
        }
        return latestEntry
    }

    private var hasHistoricalEntriesForHero: Bool {
        if isHeroUITestFirstRun {
            return false
        }
        if isHeroUITestEmptyToday {
            return true
        }
        return !allEntries.isEmpty
    }

    private var isHeroUITestEmptyToday: Bool {
        ProcessInfo.processInfo.arguments.contains("-HeroNudgeEmptyToday")
    }

    private var isHeroUITestFirstRun: Bool {
        ProcessInfo.processInfo.arguments.contains("-HeroNudgeFirstRun")
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

    private var isHeroRecordingActive: Bool {
        heroRecordingPromptID != nil && recordingState != .idle
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            OffRecordColor.appBackgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Header
                        headerSection

                        // Entry Card
                        entryCardSection

                        // Show prompts whenever the recorder is ready.
                        if recordingState == .idle {
                            promptsSection
                        }
                    }
                    .padding(.horizontal, OffRecordSpacing.screenX)
                    .padding(.top, OffRecordSpacing.screenY)
                    .padding(.bottom, compactTabSelection == nil ? OffRecordSpacing.xl : OffRecordCompactTabBarLayout.todayDockScrollContentBottomPadding)
                    .frame(maxWidth: isIPad ? 700 : .infinity)
                    .frame(maxWidth: .infinity)
                }

                if compactTabSelection == nil {
                    Spacer(minLength: 0)

                    // Recording controls at bottom
                    recordingSection
                }
            }

            if let compactTabSelection {
                compactBottomDock(selectedTab: compactTabSelection)
            }
        }
        .alert("Recording Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "")
        }
        .onReceive(NotificationCenter.default.publisher(for: .startRecordingFromSiri)) { _ in
            // Auto-start recording when triggered from Siri shortcut
            if recordingState == .idle {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    toggleRecording()
                }
            }
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
            proactiveReflection.refreshIfNeeded(entries: Array(allEntries))
            refreshHero(recordExposure: true)
        }
        .onChange(of: allEntries.count) { _, _ in
            proactiveReflection.refreshIfNeeded(entries: Array(allEntries))
        }
        .onChange(of: latestEntry?.objectID) { _, _ in
            guard !isHeroRecordingActive else { return }
            refreshHero(recordExposure: true)
        }
        .onChange(of: recordingState) { _, newState in
            if newState == .idle, heroRecordingPromptID != nil {
                heroRecordingPromptID = nil
                activeHeroPromptID = nil
                refreshHero(recordExposure: true)
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Top row with greeting and privacy badge
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(greeting)
                        .font(OffRecordTypography.bodyMedium)
                        .foregroundColor(OffRecordColor.textSecondary)
                    Text(formattedToday)
                        .font(OffRecordTypography.screenTitle)
                        .foregroundColor(OffRecordColor.textHeading)
                }
                Spacer()
                OffRecordPrivacyBadge(compact: true)
            }

            // Stats row
            HStack(spacing: 12) {
                if streakCount > 0 {
                    StatBadge(
                        icon: "flame.fill",
                        value: "\(streakCount) day streak",
                        style: .journal
                    )
                }

                if daysRecordedThisYear > 0 {
                    StatBadge(
                        icon: "calendar",
                        value: "\(daysRecordedThisYear) this year",
                        style: .privacy
                    )
                }

                Spacer()
            }
        }
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

    // MARK: - Prompts Section

    private var promptsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Need a nudge?")
                    .font(OffRecordTypography.labelMedium)
                    .foregroundColor(OffRecordColor.textBrand)
                Spacer()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(EntryPrompt.defaultPrompts) { prompt in
                        PromptChip(
                            prompt: prompt,
                            isSelected: prompt == selectedPrompt
                        ) {
                            if selectedPrompt == prompt {
                                selectedPrompt = nil
                            } else {
                                selectedPrompt = prompt
                                HapticManager.shared.selectionChanged()
                            }
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    // MARK: - Entry Card Section

    private var entryCardSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let entry = effectiveLatestEntry, !isHeroRecordingActive {
                todaysEntryCard(entry)
                if let hero = currentHero {
                    CompactDaypartHeroCard(
                        hero: hero,
                        isIPad: isIPad,
                        onRecord: { startHeroRecording(hero) },
                        onAddNote: { startTypedNote(from: hero) },
                        onSkip: { skipHero(hero) }
                    )
                }
            } else {
                if !hasHistoricalEntriesForHero, let hero = currentHero {
                    WelcomeDaypartHeroCard(
                        hero: hero,
                        authorName: authorName,
                        isIPad: isIPad,
                        isRecording: heroRecordingPromptID == hero.prompt.id && recordingState == .recording,
                        isProcessing: heroRecordingPromptID == hero.prompt.id && recordingState == .processing,
                        currentTime: recorder.currentTime,
                        level: Double(recorder.level),
                        onPrimary: { startHeroRecording(hero) },
                        onWrite: { startTypedNote(from: hero) },
                        onSkip: { skipHero(hero) },
                        onStop: stopHeroRecording
                    )
                } else if let hero = currentHero {
                    LargeDaypartHeroCard(
                        hero: hero,
                        isIPad: isIPad,
                        isRecording: heroRecordingPromptID == hero.prompt.id && recordingState == .recording,
                        isProcessing: heroRecordingPromptID == hero.prompt.id && recordingState == .processing,
                        currentTime: recorder.currentTime,
                        level: Double(recorder.level),
                        onPrimary: { startHeroRecording(hero) },
                        onWrite: { startTypedNote(from: hero) },
                        onSkip: { skipHero(hero) },
                        onStop: stopHeroRecording
                    )
                } else {
                    WelcomeCard()
                }

                ProactiveReflectionPromptCard(
                    entries: Array(allEntries),
                    hasEntryToday: effectiveLatestEntry != nil
                ) { insight in
                    startTypedNote(promptContext: insight.prompt, heroPromptID: nil)
                }
            }
        }
    }

    private func todaysEntryCard(_ entry: DiaryEntry) -> some View {
        NavigationLink {
            EntryDetailView(entry: entry)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Today's Entry", systemImage: "doc.text")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(OffRecordColor.textPeach)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(OffRecordColor.textTertiary)
                }

                if let text = entry.text, !text.isEmpty {
                    Text(text)
                        .font(.body)
                        .foregroundColor(OffRecordColor.textPrimary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(nil)

                    HStack(spacing: 16) {
                        if let duration = entry.value(forKey: "duration") as? Double, duration > 0 {
                            Label(formatDuration(duration), systemImage: "waveform")
                                .font(.caption)
                                .foregroundColor(OffRecordColor.textSecondary)
                        }

                        let words = wordCount(for: text)
                        if words > 0 {
                            Label("\(words) words", systemImage: "text.word.spacing")
                                .font(.caption)
                                .foregroundColor(OffRecordColor.textSecondary)
                        }

                        Spacer()

                        if let updatedAt = entry.updatedAt {
                            Text(formattedTime(updatedAt))
                                .font(.caption)
                                .foregroundColor(OffRecordColor.textTertiary)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        if recordingState == .processing {
                            HStack(spacing: 10) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Transcribing your recording...")
                                    .font(.subheadline)
                                    .foregroundColor(OffRecordColor.textSecondary)
                            }
                        } else {
                            emptyEntryCopy(for: entry)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .offRecordContentCard(cornerRadius: OffRecordRadius.xl, fill: OffRecordColor.surfacePeach)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Recording Section

    private func compactBottomDock(selectedTab: Binding<OffRecordTab>) -> some View {
        VStack(spacing: 12) {
            compactRecordingFeedback

            ZStack(alignment: .bottom) {
                compactActionShelf
                    .offset(y: -54)
                    .zIndex(1)

                OffRecordFloatingTabBar(selectedTab: selectedTab)
                    .zIndex(2)

                compactRecordButton
                    .offset(y: -92)
                    .zIndex(3)
            }
        }
        .padding(.horizontal, OffRecordCompactTabBarLayout.horizontalPadding)
        .padding(.bottom, OffRecordCompactTabBarLayout.bottomPadding)
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: recordingState)
    }

    @ViewBuilder
    private var compactRecordingFeedback: some View {
        if recordingState == .processing && !isHeroRecordingActive {
            HStack(spacing: 10) {
                ProgressView()
                    .scaleEffect(0.9)
                Text("Transcribing your thoughts...")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(OffRecordColor.textSecondary)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
            .background(OffRecordColor.surfacePrimary.opacity(0.94), in: Capsule())
            .overlay(Capsule().stroke(OffRecordColor.borderSoft, lineWidth: 1))
            .shadow(color: OffRecordShadow.floatingColor, radius: 18, x: 0, y: 8)
            .transition(.scale.combined(with: .opacity))
        } else if recordingState == .recording && !isHeroRecordingActive {
            HeroRecordingMeter(
                currentTime: recorder.currentTime,
                level: Double(recorder.level),
                isProcessing: false,
                barCount: 20
            )
            .frame(maxWidth: 320)
            .padding(.horizontal, 28)
            .transition(.scale.combined(with: .opacity))
        }
    }

    private var compactActionShelf: some View {
        HStack {
            compactPhotoButton

            Spacer(minLength: 92)

            compactNoteButton
        }
        .padding(.horizontal, 36)
        .frame(maxWidth: 340)
        .frame(height: 92)
        .background(
            RoundedRectangle(cornerRadius: OffRecordRadius.xxl, style: .continuous)
                .fill(OffRecordColor.surfacePrimary.opacity(0.94))
                .overlay(
                    RoundedRectangle(cornerRadius: OffRecordRadius.xxl, style: .continuous)
                        .stroke(OffRecordColor.borderSoft, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 24, x: 0, y: 8)
        )
        .padding(.horizontal, 24)
    }

    private var compactPhotoButton: some View {
        PhotosPicker(
            selection: $selectedPhotos,
            maxSelectionCount: 5,
            matching: .images
        ) {
            compactSideActionButton(systemImage: "photo.badge.plus")
        }
        .onChange(of: selectedPhotos) { _, newItems in
            handlePhotoPickerSelection(newItems)
        }
        .buttonStyle(.plain)
        .disabled(recordingState != .idle)
        .opacity(recordingState == .idle ? 1 : 0.45)
        .accessibilityLabel("Add photos")
        .accessibilityIdentifier("todayDock.photo")
    }

    private var compactNoteButton: some View {
        Button(action: startTypedNote) {
            compactSideActionButton(systemImage: "square.and.pencil")
        }
        .buttonStyle(.plain)
        .disabled(recordingState != .idle)
        .opacity(recordingState == .idle ? 1 : 0.45)
        .accessibilityLabel("Write note")
        .accessibilityIdentifier("todayDock.write")
    }

    private func compactSideActionButton(systemImage: String) -> some View {
        ZStack {
            Circle()
                .fill(OffRecordColor.backgroundSageTint)

            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(OffRecordColor.brandSageDark)
        }
        .frame(width: 60, height: 60)
        .contentShape(Circle())
    }

    private var compactRecordButton: some View {
        Button {
            if recordingState != .processing {
                toggleRecording()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(OffRecordColor.brandPlum)
                    .frame(width: 92, height: 92)

                Circle()
                    .stroke(OffRecordColor.surfacePrimary, lineWidth: 4)
                    .frame(width: 92, height: 92)

                if recordingState == .recording {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(OffRecordColor.textInverse)
                        .frame(width: 30, height: 30)
                } else if recordingState == .processing {
                    ProgressView()
                        .tint(OffRecordColor.textInverse)
                } else {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundColor(OffRecordColor.textInverse)
                }
            }
            .frame(width: 92, height: 92)
            .shadow(color: Color.black.opacity(0.12), radius: 18, x: 0, y: 8)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(recordingState == .recording ? "Stop recording" : "Start recording")
        .accessibilityIdentifier("todayDock.record")
    }

    private var recordingSection: some View {
        VStack(spacing: 16) {
            // Processing indicator
            if recordingState == .processing && !isHeroRecordingActive {
                HStack(spacing: 10) {
                    ProgressView()
                        .scaleEffect(0.9)
                    Text("Transcribing your thoughts...")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(OffRecordColor.textSecondary)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 20)
                .offRecordGlassControl(tint: OffRecordColor.brandLavenderDark, in: Capsule(), fallbackFill: OffRecordColor.surfaceLavender)
                .transition(.scale.combined(with: .opacity))
            }

            // Audio level meter (when recording)
            if recordingState == .recording && !isHeroRecordingActive {
                HeroRecordingMeter(
                    currentTime: recorder.currentTime,
                    level: Double(recorder.level),
                    isProcessing: false,
                    barCount: isIPad ? 30 : 20
                )
                .transition(.scale.combined(with: .opacity))
            }

            // Entry action buttons
            HStack(spacing: 24) {
                Spacer()

                if recordingState == .idle {
                    photoButton
                }

                recordButton

                if recordingState == .idle {
                    noteButton
                }

                Spacer()
            }

            // Status text (only when idle)
            if recordingState == .idle {
                VStack(spacing: 6) {
                    Text(statusText)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(OffRecordColor.textBrand)
                    Text("Your journal stays on this device")
                        .font(.caption)
                        .foregroundColor(OffRecordColor.textSage)

                    if let prompt = selectedPrompt {
                        Text(prompt.detail)
                            .font(.caption)
                            .foregroundColor(OffRecordColor.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                    }
                }
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 20)
        .frame(maxWidth: isIPad ? 560 : .infinity)
        .background(
            RoundedRectangle(cornerRadius: OffRecordRadius.xxl, style: .continuous)
                .fill(OffRecordColor.todayCaptureGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: OffRecordRadius.xxl, style: .continuous)
                        .stroke(OffRecordColor.borderWarm, lineWidth: 1)
                )
                .shadow(color: OffRecordShadow.floatingColor, radius: 24, x: 0, y: 10)
        )
        .padding(.horizontal)
        .padding(.bottom, 8)
        .safeAreaPadding(.bottom, 4)
        .animation(.spring(response: 0.4), value: recordingState)
    }

    private var recordButtonSize: CGFloat { isIPad ? 88 : 72 }
    private var recordButtonOuterSize: CGFloat { isIPad ? 108 : 88 }
    private var sideActionButtonSize: CGFloat { isIPad ? 56 : 48 }

    private var photoButton: some View {
        PhotosPicker(
            selection: $selectedPhotos,
            maxSelectionCount: 5,
            matching: .images
        ) {
            sideActionButton(systemImage: "photo.badge.plus")
        }
        .onChange(of: selectedPhotos) { _, newItems in
            handlePhotoPickerSelection(newItems)
        }
        .accessibilityLabel("Add photos")
    }

    private var noteButton: some View {
        Button(action: startTypedNote) {
            sideActionButton(systemImage: "square.and.pencil")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Write note")
    }

    private func sideActionButton(systemImage: String) -> some View {
        ZStack {
            Image(systemName: systemImage)
                .font(.system(size: isIPad ? 22 : 18))
                .foregroundColor(sideActionIconColor)
        }
        .frame(width: sideActionButtonSize, height: sideActionButtonSize)
        .offRecordReadableGlassControl(.brand, in: Circle())
    }

    private var recordButton: some View {
        Button {
            if recordingState != .processing {
                toggleRecording()
            }
        } label: {
            ZStack {
                if #available(iOS 26.0, *) {
                    Circle()
                        .stroke(buttonColor.opacity(0.35), lineWidth: 4)
                        .frame(width: recordButtonOuterSize, height: recordButtonOuterSize)
                } else {
                    Circle()
                        .fill(buttonColor)
                        .frame(width: recordButtonSize, height: recordButtonSize)

                    Circle()
                        .stroke(buttonColor.opacity(0.3), lineWidth: 4)
                        .frame(width: recordButtonOuterSize, height: recordButtonOuterSize)
                }

                // Icon
                if recordingState == .recording {
                    // Stop square
                    RoundedRectangle(cornerRadius: 6)
                        .fill(recordIconColor)
                        .frame(width: isIPad ? 30 : 24, height: isIPad ? 30 : 24)
                } else if recordingState == .processing {
                    ProgressView()
                        .tint(recordIconColor)
                } else {
                    // Mic icon
                    Image(systemName: "mic.fill")
                        .font(.system(size: isIPad ? 34 : 28))
                        .foregroundColor(recordIconColor)
                }
            }
            .frame(width: recordButtonOuterSize, height: recordButtonOuterSize)
            .offRecordGlassControl(tint: buttonColor, in: Circle(), fallbackFill: buttonColor)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(recordingState == .recording ? "Stop recording" : "Start recording")
    }

    private var recordIconColor: Color {
        .white
    }

    private var sideActionIconColor: Color {
        OffRecordReadableTintStyle.brand.foreground
    }

    private var buttonColor: Color {
        switch recordingState {
        case .idle: return OffRecordColor.brandPlum
        case .recording: return OffRecordColor.brandCoral
        case .processing: return OffRecordColor.brandPeach
        }
    }

    private var statusText: String {
        switch recordingState {
        case .idle: return "Tap to record or write"
        case .recording: return "Tap to stop"
        case .processing: return "Almost done..."
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let normalizedLevel = CGFloat(max(0, min(1, recorder.level)))
        let baseHeight: CGFloat = 8
        let maxAdditional: CGFloat = 22

        // Create wave effect based on index
        let wave = sin(Double(index) * 0.5 + Date().timeIntervalSince1970 * 8) * 0.3 + 0.7
        return baseHeight + maxAdditional * normalizedLevel * CGFloat(wave)
    }

    private func barColor(for index: Int) -> Color {
        let normalizedLevel = CGFloat(max(0, min(1, recorder.level)))
        let barCount = CGFloat(isIPad ? 30 : 20)
        let threshold = CGFloat(index) / barCount

        if normalizedLevel > threshold {
            let highThreshold = Int(barCount * 0.7)
            let midThreshold = Int(barCount * 0.5)
            return index > highThreshold ? OffRecordColor.brandCoral : (index > midThreshold ? OffRecordColor.brandPeach : OffRecordColor.brandAqua)
        }
        return OffRecordColor.textTertiary.opacity(0.2)
    }

    // MARK: - Photo Handling

    private func handlePhotoPickerSelection(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }

        // Get or create today's entry
        let entry = getOrCreateTodayEntry()

        for item in items {
            item.loadTransferable(type: Data.self) { result in
                if case .success(let data) = result, let data, let image = UIImage(data: data) {
                    DispatchQueue.main.async {
                        if PhotoStorageManager.shared.addPhoto(image, to: entry, in: viewContext) != nil {
                            entry.updatedAt = Date()
                            try? viewContext.save()
                            HapticManager.shared.entrySaved()
                        }
                    }
                }
            }
        }
        selectedPhotos = []
    }

    private func startTypedNote() {
        startTypedNote(promptContext: selectedPrompt?.detail, heroPromptID: nil)
    }

    private func startTypedNote(from hero: SelectedDaypartHero) {
        startTypedNote(promptContext: hero.prompt.prompt, heroPromptID: hero.prompt.id)
    }

    private func startTypedNote(promptContext: String?, heroPromptID: String?) {
        guard recordingState == .idle else { return }

        let hadEntry = latestEntry != nil
        let entry = getOrCreateTodayEntry()
        noteEntry = entry
        notePromptContext = promptContext
        noteHeroPromptID = heroPromptID
        shouldDeleteEmptyNoteDraft = !hadEntry && entryHasNoContent(entry)
        isShowingNoteEditor = true
        HapticManager.shared.selectionChanged()
    }

    private func startHeroRecording(_ hero: SelectedDaypartHero) {
        guard recordingState == .idle else { return }
        activeHeroPromptID = hero.prompt.id
        heroRecordingPromptID = hero.prompt.id
        startRecording()
    }

    private func stopHeroRecording() {
        guard recordingState == .recording else { return }
        stopRecording()
    }

    private func skipHero(_ hero: SelectedDaypartHero) {
        guard recordingState == .idle else { return }
        heroStore.recordSkip(promptID: hero.prompt.id)
        selectedHero = DaypartHeroLibrary.selectHero(
            dayPart: DayPart.current(),
            hasEntryToday: effectiveLatestEntry != nil,
            store: heroStore
        )
        if let selectedHero {
            heroStore.recordExposure(selectedHero)
        }
        HapticManager.shared.selectionChanged()
    }

    private func refreshHero(recordExposure: Bool) {
        selectedHero = DaypartHeroLibrary.selectHero(
            dayPart: DayPart.current(),
            hasEntryToday: effectiveLatestEntry != nil,
            store: heroStore
        )
        if recordExposure, let selectedHero {
            heroStore.recordExposure(selectedHero)
        }
    }

    private func getOrCreateTodayEntry() -> DiaryEntry {
        if let existing = latestEntry {
            return existing
        }
        let now = Date()
        let entry = DiaryEntry(context: viewContext)
        entry.id = UUID()
        entry.date = now
        entry.createdAt = now
        entry.text = ""
        entry.isStarred = false
        entry.updatedAt = now
        try? viewContext.save()
        return entry
    }

    @ViewBuilder
    private func emptyEntryCopy(for entry: DiaryEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if hasAudioReference(entry) {
                Text("Recording saved")
                    .font(.subheadline)
                    .foregroundColor(OffRecordColor.textPrimary)
                Text("Tap to add text or play your recording")
                    .font(.caption)
                    .foregroundColor(OffRecordColor.textSecondary)
            } else if entry.photos?.count ?? 0 > 0 {
                Text("Photos added")
                    .font(.subheadline)
                    .foregroundColor(OffRecordColor.textPrimary)
                Text("Tap to add text or more photos")
                    .font(.caption)
                    .foregroundColor(OffRecordColor.textSecondary)
            } else {
                Text("Draft note")
                    .font(.subheadline)
                    .foregroundColor(OffRecordColor.textPrimary)
                Text("Tap to start writing")
                    .font(.caption)
                    .foregroundColor(OffRecordColor.textSecondary)
            }
        }
    }

    private func hasAudioReference(_ entry: DiaryEntry) -> Bool {
        (entry.value(forKey: "audioFileName") as? String)?.isEmpty == false
    }

    private func entryHasNoContent(_ entry: DiaryEntry) -> Bool {
        let text = entry.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let duration = entry.value(forKey: "duration") as? Double ?? 0
        let photoCount = entry.photos?.count ?? 0
        return text.isEmpty && !hasAudioReference(entry) && duration <= 0 && photoCount == 0
    }

    // MARK: - Recording Logic

    private func toggleRecording() {
        switch recordingState {
        case .idle:
            startRecording()
        case .recording:
            stopRecording()
        case .processing:
            break
        }
    }

    private func startRecording() {
        if ProcessInfo.processInfo.arguments.contains("-HeroNudgeUITest") {
            recordingState = .recording
            HapticManager.shared.recordingStarted()
            return
        }

        #if os(iOS)
        AVAudioApplication.requestRecordPermission { granted in
            DispatchQueue.main.async {
                if granted {
                    do {
                        try self.recorder.startRecording()
                        self.recordingState = .recording
                        HapticManager.shared.recordingStarted()
                    } catch {
                        self.errorMessage = "Unable to start recording. Please try again."
                        self.heroRecordingPromptID = nil
                        self.activeHeroPromptID = nil
                        HapticManager.shared.error()
                    }
                } else {
                    self.errorMessage = "OffRecord AI Journal needs microphone access to record your diary."
                    self.heroRecordingPromptID = nil
                    self.activeHeroPromptID = nil
                    HapticManager.shared.warning()
                }
            }
        }
        #else
        errorMessage = "Recording is only available on iOS."
        #endif
    }

    private func stopRecording() {
        HapticManager.shared.recordingStopped()

        if let result = recorder.stopRecording() {
            recordingState = .processing
            saveEntry(audioURL: result.url, duration: result.duration)
        } else {
            recordingState = .idle
            heroRecordingPromptID = nil
            activeHeroPromptID = nil
        }
    }

    private func saveEntry(audioURL: URL, duration: TimeInterval) {
        let now = Date()
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: now)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? now

        let fetchRequest: NSFetchRequest<DiaryEntry> = DiaryEntry.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "date >= %@ AND date < %@", startOfDay as NSDate, endOfDay as NSDate)
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        fetchRequest.fetchLimit = 1

        let entry: DiaryEntry
        if let existing = (try? viewContext.fetch(fetchRequest))?.first {
            entry = existing
        } else {
            entry = DiaryEntry(context: viewContext)
            entry.id = UUID()
            entry.date = now
            entry.createdAt = now
            entry.text = ""
            entry.isStarred = false
        }

        entry.updatedAt = now
        entry.setValue(audioURL.lastPathComponent, forKey: "audioFileName")
        let existingDuration = entry.value(forKey: "duration") as? Double ?? 0
        entry.setValue(existingDuration + duration, forKey: "duration")

        do {
            try viewContext.save()
            // Clear any selected prompt once an entry has been saved
            selectedPrompt = nil
        } catch {
            logger.error("Failed to save entry: \(error.localizedDescription)")
            recordingState = .idle
            return
        }

        #if os(iOS)
        SpeechTranscriber.shared.transcribe(from: audioURL) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let textSegment):
                    let existingText = entry.text ?? ""
                    if existingText.isEmpty {
                        entry.text = textSegment
                    } else {
                        entry.text = existingText + "\n\n" + textSegment
                    }
                    entry.updatedAt = Date()
                    do {
                        try viewContext.save()
                        heroStore.recordPromptResponse(
                            promptID: activeHeroPromptID,
                            wordCount: wordCount(for: textSegment)
                        )
                        HapticManager.shared.entrySaved()
                        ReviewManager.shared.recordEntry()

                        // Feed into Friday for learning
                        FridayAssistantEngine.shared.processEntry(
                            text: textSegment,
                            mood: entry.mood,
                            date: entry.date ?? Date(),
                            duration: entry.duration
                        )
                        SemanticMemoryIndexController.shared.upsertEntry(entry)
                    } catch {
                        logger.error("Failed to update entry with transcription: \(error.localizedDescription)")
                    }
                case .failure(let error):
                    logger.error("Transcription failed: \(error.localizedDescription)")
                    // Show user-friendly message for offline/transcription errors
                    if let transcriptionError = error as? SpeechTranscriber.TranscriptionError {
                        self.errorMessage = transcriptionError.errorDescription
                    } else {
                        self.errorMessage = "Transcription failed. Your recording is saved—tap the entry to add text manually."
                    }
                }
                recordingState = .idle
            }
        }
        #else
        recordingState = .idle
        #endif
    }

    // MARK: - Formatting

    private var formattedToday: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: Date())
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }

    private func wordCount(for text: String) -> Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }

    // MARK: - Stats

    private var daysRecordedThisYear: Int {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())

        let days: Set<Date> = Set(allEntries.compactMap { entry in
            guard let date = entry.date else { return nil }
            return calendar.startOfDay(for: date)
        })

        return days.filter { calendar.component(.year, from: $0) == currentYear }.count
    }

    private var streakCount: Int {
        let calendar = Calendar.current

        let daysSet: Set<Date> = Set(allEntries.compactMap { entry in
            guard let date = entry.date else { return nil }
            return calendar.startOfDay(for: date)
        })

        var days = Array(daysSet)
        guard !days.isEmpty else { return 0 }
        days.sort(by: >)

        var streak = 1
        for i in 1..<days.count {
            let diff = calendar.dateComponents([.day], from: days[i], to: days[i - 1]).day ?? 0
            if diff == 1 {
                streak += 1
            } else {
                break
            }
        }
        return streak
    }
}

// MARK: - Stat Badge Component

struct StatBadge: View {
    let icon: String
    let value: String
    let style: OffRecordReadableTintStyle

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
            Text(value)
                .font(.caption)
        }
        .foregroundColor(style.foreground)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .offRecordGlassControl(
            tint: style.tint,
            in: Capsule(),
            fallbackFill: style.fill,
            border: style.border
        )
    }
}

struct EntryPrompt: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let detail: String

    static let defaultPrompts: [EntryPrompt] = [
        EntryPrompt(
            title: "Daily reflection",
            detail: "What is one moment from today that you want to remember?"
        ),
        EntryPrompt(
            title: "Gratitude",
            detail: "What are three small things you feel grateful for right now?"
        ),
        EntryPrompt(
            title: "Energy check",
            detail: "How does your body feel today - tense, tired, or calm?"
        ),
        EntryPrompt(
            title: "Letting go",
            detail: "What is one worry you can gently put down for tonight?"
        ),
        EntryPrompt(
            title: "Self-kindness",
            detail: "If you spoke to yourself like a friend, what would you say?"
        ),
        EntryPrompt(
            title: "Tomorrow",
            detail: "What is one gentle intention you have for tomorrow?"
        )
    ]
}

struct PromptChip: View {
    let prompt: EntryPrompt
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                Text(prompt.title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(isSelected ? OffRecordReadableTintStyle.friday.foreground : OffRecordColor.textPrimary)
                Text(prompt.detail)
                    .font(.caption)
                    .foregroundColor(OffRecordColor.textSecondary)
                    .lineLimit(2)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: 280, alignment: .leading)
            .offRecordGlassControl(
                tint: isSelected ? OffRecordReadableTintStyle.friday.tint : OffRecordReadableTintStyle.neutral.tint,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous),
                fallbackFill: isSelected ? OffRecordReadableTintStyle.friday.fill : OffRecordReadableTintStyle.neutral.fill,
                border: isSelected ? OffRecordReadableTintStyle.friday.border : OffRecordReadableTintStyle.neutral.border
            )
        }
        .buttonStyle(.plain)
    }
}
