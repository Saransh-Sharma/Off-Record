//
//  OnboardingView.swift
//  OffRecord
//
//  Questionnaire-style first launch experience.
//

import SwiftUI
import CoreData
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

private struct PendingOnboardingTranscription {
    let entryObjectID: NSManagedObjectID
    let audioURL: URL
}

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ObservedObject private var lockManager = AppLockManager.shared
    @ObservedObject private var reminderManager = ReminderManager.shared
    @ObservedObject private var goalManager = GoalManager.shared
    @StateObject private var recorder = AudioRecorder()

    @AppStorage("authorName") private var authorName: String = ""

    @State private var store = OnboardingStore()
    @State private var response = OnboardingStore.load()
    @State private var step: OnboardingStep = .welcome
    @State private var nameDraft = ""
    @State private var firstEntryDraft = ""
    @State private var selectedMood: Mood = .calm
    @State private var isRecording = false
    @State private var isTranscribing = false
    @State private var entryCreated = false
    @State private var firstEntryMode: FirstEntryMode = .voice
    @State private var onboardingError: String?
    @State private var showNotificationDeniedAlert = false
    @State private var firstEntryAudioEntryID: NSManagedObjectID?
    @State private var pendingTranscription: PendingOnboardingTranscription?
    @State private var showSpeechConsentPrompt = false

    private var isIPad: Bool { horizontalSizeClass == .regular }

    var body: some View {
        ZStack {
            ConcentricPageTransitionView(
                pages: concentricPages,
                currentIndex: stepIndex,
                duration: reduceMotion ? 0.01 : 0.86,
                ctaTitle: primaryTitle,
                ctaIcon: primaryIcon ?? "chevron.forward",
                isCTADisabled: isPrimaryDisabled,
                secondaryTitle: secondaryTitle,
                onPrimaryAction: primaryAction,
                onSecondaryAction: secondaryAction
            )
        }
        .overlay(alignment: .top) {
            OnboardingProgressHeader(
                step: step,
                canGoBack: step.canGoBack,
                onBack: goBack
            )
            .padding(.horizontal, isIPad ? 44 : 20)
            .padding(.top, 14)
        }
        .foregroundStyle(OffRecordColor.textBrand)
        .onAppear {
            nameDraft = authorName
            firstEntryDraft = response.firstEntryText
            if response.microphoneChoice == .denied {
                firstEntryMode = .textFallback
            }
        }
        .onChange(of: response) { _, newValue in
            store.save(newValue)
        }
        .onChange(of: step) { _, newStep in
            guard newStep == .processing else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.25 : 1.45)) {
                if step == .processing {
                    goForward()
                }
            }
        }
        .alert("OffRecord could not continue", isPresented: Binding(
            get: { onboardingError != nil },
            set: { if !$0 { onboardingError = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(onboardingError ?? "")
        }
        .alert("Notifications Disabled", isPresented: $showNotificationDeniedAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("You can enable reminders later in Settings. OffRecord still works fully offline.")
        }
        .alert(SpeechTranscriptionConsent.disclosureTitle, isPresented: $showSpeechConsentPrompt) {
            Button("Agree and Transcribe") {
                SpeechTranscriptionConsent.grantAppleSpeechProcessing()
                resumePendingTranscription()
            }
            Button("Save Recording Only", role: .cancel) {
                keepPendingRecordingOnly()
            }
        } message: {
            Text(SpeechTranscriptionConsent.disclosureMessage)
        }
        .ignoresSafeArea(.keyboard)
    }

    private var stepIndex: Binding<Int> {
        Binding(
            get: { step.rawValue },
            set: { newValue in
                guard let newStep = OnboardingStep(rawValue: newValue) else { return }
                step = newStep
            }
        )
    }

    private var concentricPages: [ConcentricPageTransitionView<AnyView>.PageContent] {
        OnboardingStep.allCases.map { step in
            (
                view: AnyView(
                    ConcentricOnboardingPage(
                        isIPad: isIPad,
                        isKeyboardAdaptive: step == .welcome,
                        scrollTargetID: step == .welcome ? OnboardingScrollTarget.welcomeNameField : nil,
                    ) {
                        currentStepContent(for: step)
                    }
                ),
                background: step.backgroundColor
            )
        }
    }

    @ViewBuilder
    private func currentStepContent(for step: OnboardingStep) -> some View {
        switch step {
        case .welcome:
            WelcomeStep(nameDraft: $nameDraft)
        case .goal:
            GoalStep(selectedGoal: $response.goal)
        case .painPoints:
            PainPointsStep(selectedPainPoints: $response.painPoints)
        case .privacyProof:
            PrivacyProofStep()
        case .faceID:
            FaceIDStep(
                biometryName: lockManager.biometryTypeName,
                isEnabled: lockManager.isEnabled,
                isAvailable: lockManager.biometricsAvailable
            )
        case .relatable:
            RelatableStep(selectedStatements: $response.relatableStatements)
        case .solution:
            PersonalizedSolutionStep(response: response)
        case .preferences:
            PreferencesStep(response: $response)
        case .microphone:
            PermissionPrimerStep(
                icon: "mic.fill",
                title: "Capture thoughts before they disappear.",
                subtitle: "Voice is the fastest way to journal honestly.",
                bullets: [
                    "Record a private reflection in seconds.",
                    "Audio stays in the app sandbox on this device.",
                    "Typing is always available if you skip microphone access."
                ]
            )
        case .speech:
            PermissionPrimerStep(
                icon: "text.bubble.fill",
                title: "Turn voice into a private journal entry.",
                subtitle: "OffRecord uses Apple Speech for transcription and asks before voice is processed.",
                bullets: [
                    "Online transcription may be processed by Apple Speech.",
                    "No account and no analytics.",
                    "Friday insights and mood analysis stay on this device."
                ]
            )
        case .processing:
            ProcessingStep()
        case .firstEntry:
            FirstEntryStep(
                recorder: recorder,
                isRecording: isRecording,
                isTranscribing: isTranscribing,
                elapsedTime: recorder.currentTime,
                level: recorder.level,
                draft: $firstEntryDraft,
                selectedMood: $selectedMood,
                mode: firstEntryMode,
                entryCreated: entryCreated,
                onRecordTap: toggleRecording
            )
        case .valueReveal:
            ValueRevealStep(response: response, entryText: firstEntryDraft, mood: selectedMood)
        case .habit:
            HabitSetupStep(
                reminderManager: reminderManager,
                goalManager: goalManager,
                onReminderDenied: { showNotificationDeniedAlert = true }
            )
        case .finish:
            FinishStep()
        }
    }

    private var primaryTitle: String {
        switch step {
        case .welcome: return "Get Started"
        case .goal, .painPoints, .relatable, .preferences: return "Continue"
        case .privacyProof: return "Keep my journal private"
        case .faceID: return lockManager.isEnabled ? "Face ID is on" : "Protect my journal with Face ID"
        case .solution: return "Build my starter map"
        case .microphone: return "Continue"
        case .speech: return "I understand"
        case .processing: return "Building..."
        case .firstEntry: return entryCreated ? "Show my starter map" : "Save my first entry"
        case .valueReveal: return "Set up my habit"
        case .habit: return "Continue"
        case .finish: return "Enter OffRecord"
        }
    }

    private var primaryIcon: String? {
        switch step {
        case .welcome, .finish:
            return "arrow.right"
        case .faceID:
            return lockManager.isEnabled ? "checkmark" : "faceid"
        case .firstEntry:
            return entryCreated ? "sparkles" : "checkmark"
        default:
            return nil
        }
    }

    private var secondaryTitle: String? {
        switch step {
        case .faceID:
            return lockManager.isEnabled ? nil : "Not now"
        case .firstEntry:
            return isRecording ? nil : "Skip first entry"
        default:
            return nil
        }
    }

    private var isPrimaryDisabled: Bool {
        switch step {
        case .goal:
            return response.goal == nil
        case .painPoints:
            return response.painPoints.isEmpty
        case .preferences:
            return response.reflectionFocus == nil || response.promptStyle == nil
        case .processing:
            return true
        case .firstEntry:
            return isRecording || isTranscribing || (!entryCreated && firstEntryDraft.trimmed.isEmpty)
        default:
            return false
        }
    }

    private func primaryAction() {
        switch step {
        case .welcome:
            authorName = Personalization.trimmedName(from: nameDraft)
            goForward()
        case .faceID:
            if lockManager.isEnabled {
                goForward()
            } else {
                enableFaceID()
            }
        case .firstEntry:
            if entryCreated {
                response.firstEntryText = firstEntryDraft.trimmed
                goForward()
            } else {
                saveTypedEntryIfNeeded()
            }
        case .finish:
            completeOnboarding()
        default:
            goForward()
        }
    }

    private func secondaryAction() {
        switch step {
        case .faceID:
            response.faceIDChoice = .skipped
            goForward()
        case .firstEntry:
            response.firstEntrySkipped = true
            goForward()
        default:
            break
        }
    }

    private func goForward() {
        guard let next = step.next else { return }
        step = next
    }

    private func goBack() {
        guard let previous = step.previous else { return }
        step = previous
    }

    private func enableFaceID() {
        lockManager.authenticate { success in
            if success {
                lockManager.isEnabled = true
                response.faceIDChoice = .enabled
                goForward()
            } else {
                response.faceIDChoice = .failed
                onboardingError = "Face ID was not enabled. You can try again or skip it for now."
            }
        }
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        #if os(iOS)
        AVAudioApplication.requestRecordPermission { granted in
            DispatchQueue.main.async {
                response.microphoneChoice = granted ? .granted : .denied
                guard granted else {
                    firstEntryMode = .textFallback
                    return
                }
                do {
                    try recorder.startRecording()
                    isRecording = true
                    HapticManager.shared.recordingStarted()
                } catch {
                    firstEntryMode = .textFallback
                    onboardingError = "Unable to start recording. Please type your first entry instead."
                    HapticManager.shared.error()
                }
            }
        }
        #else
        firstEntryMode = .textFallback
        onboardingError = "Recording is only available on iOS."
        #endif
    }

    private func stopRecording() {
        guard let result = recorder.stopRecording() else {
            isRecording = false
            return
        }

        isRecording = false
        isTranscribing = true
        HapticManager.shared.recordingStopped()
        let entry = createEntry(text: "", audioFileName: result.url.lastPathComponent, duration: result.duration)
        firstEntryAudioEntryID = entry.objectID

        beginTranscription(entry: entry, audioURL: result.url)
    }

    private func beginTranscription(entry: DiaryEntry, audioURL: URL) {
        guard SpeechTranscriptionConsent.hasGrantedAppleSpeechProcessing else {
            pendingTranscription = PendingOnboardingTranscription(entryObjectID: entry.objectID, audioURL: audioURL)
            firstEntryMode = .textFallback
            isTranscribing = false
            showSpeechConsentPrompt = true
            return
        }

        transcribeFirstEntry(entry: entry, audioURL: audioURL)
    }

    private func resumePendingTranscription() {
        guard let pendingTranscription else {
            isTranscribing = false
            return
        }

        self.pendingTranscription = nil
        guard let entry = try? viewContext.existingObject(with: pendingTranscription.entryObjectID) as? DiaryEntry else {
            isTranscribing = false
            return
        }

        isTranscribing = true
        firstEntryMode = .voice
        transcribeFirstEntry(entry: entry, audioURL: pendingTranscription.audioURL)
    }

    private func keepPendingRecordingOnly() {
        pendingTranscription = nil
        isTranscribing = false
        firstEntryMode = .textFallback
    }

    private func transcribeFirstEntry(entry: DiaryEntry, audioURL: URL) {
        isTranscribing = true
        SpeechTranscriber.shared.transcribe(from: audioURL) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let text):
                    response.speechChoice = .granted
                    firstEntryDraft = text
                    response.firstEntryText = text
                    entry.text = text
                    entry.setValue(selectedMood.rawValue, forKey: "mood")
                    entry.updatedAt = Date()
                    try? viewContext.save()
                    EntryLearningPipeline.processSavedEntry(
                        text: text,
                        mood: selectedMood.rawValue,
                        date: entry.date ?? Date(),
                        duration: entry.duration
                    )
                    EntryLearningPipeline.upsertSemanticEntry(entry)
                    HapticManager.shared.entrySaved()
                case .failure:
                    response.speechChoice = .denied
                    onboardingError = "Your recording was saved, but transcription did not finish. You can type a few words before continuing."
                    firstEntryMode = .textFallback
                }
                isTranscribing = false
            }
        }
    }

    private func saveTypedEntryIfNeeded() {
        let text = firstEntryDraft.trimmed
        guard !text.isEmpty else { return }

        let entry: DiaryEntry
        if let firstEntryAudioEntryID,
           let existingEntry = try? viewContext.existingObject(with: firstEntryAudioEntryID) as? DiaryEntry {
            existingEntry.text = text
            existingEntry.updatedAt = Date()
            existingEntry.setValue(selectedMood.rawValue, forKey: "mood")
            try? viewContext.save()
            entry = existingEntry
        } else {
            entry = createEntry(text: text, audioFileName: nil, duration: 0)
        }
        entryCreated = true
        response.firstEntryText = text
        EntryLearningPipeline.processSavedEntry(
            text: text,
            mood: selectedMood.rawValue,
            date: entry.date ?? Date(),
            duration: 0
        )
        EntryLearningPipeline.upsertSemanticEntry(entry)
        HapticManager.shared.entrySaved()
        goForward()
    }

    @discardableResult
    private func createEntry(text: String, audioFileName: String?, duration: TimeInterval) -> DiaryEntry {
        let now = Date()
        let entry = DiaryEntry(context: viewContext)
        entry.id = UUID()
        entry.date = now
        entry.createdAt = now
        entry.updatedAt = now
        entry.text = text
        entry.isStarred = false
        entry.setValue(audioFileName, forKey: "audioFileName")
        entry.setValue(duration, forKey: "duration")
        entry.setValue(selectedMood.rawValue, forKey: "mood")
        try? viewContext.save()
        return entry
    }

    private func completeOnboarding() {
        authorName = Personalization.trimmedName(from: nameDraft)
        response.completedAt = Date()
        store.save(response)
        withAnimation(.easeInOut(duration: 0.3)) {
            hasCompletedOnboarding = true
        }
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
    }
}

// MARK: - Flow State

enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome
    case goal
    case painPoints
    case privacyProof
    case faceID
    case relatable
    case solution
    case preferences
    case microphone
    case speech
    case processing
    case firstEntry
    case valueReveal
    case habit
    case finish

    var id: Int { rawValue }

    var previous: OnboardingStep? {
        OnboardingStep(rawValue: rawValue - 1)
    }

    var next: OnboardingStep? {
        OnboardingStep(rawValue: rawValue + 1)
    }

    var canGoBack: Bool {
        self != .welcome && self != .processing
    }

    var progress: Double {
        Double(rawValue + 1) / Double(Self.allCases.count)
    }

    var progressText: String {
        "\(rawValue + 1) of \(Self.allCases.count)"
    }

    var pageTitle: String {
        switch self {
        case .welcome: return "Understand yourself, privately."
        case .goal: return "What do you want your journal to help with?"
        case .painPoints: return "What usually stops you from journaling honestly?"
        case .privacyProof: return "Local by design. Clear when Apple Speech is used."
        case .faceID: return "Protect your journal before you write."
        case .relatable: return "Which statements sound like you?"
        case .solution: return "A smarter way to reflect, built around you."
        case .preferences: return "What should Friday pay attention to first?"
        case .microphone: return "Capture thoughts before they disappear."
        case .speech: return "Turn voice into a private journal entry."
        case .processing: return "Building..."
        case .firstEntry: return "Say one honest thing about today."
        case .valueReveal: return "Friday has enough to start listening for patterns."
        case .habit: return "Make reflection easy to repeat."
        case .finish: return "Your private journal is ready."
        }
    }

    var backgroundColor: Color {
        switch self {
        case .welcome:
            return OffRecordColor.moodCalm
        case .goal:
            return OffRecordColor.moodGreat
        case .painPoints:
            return OffRecordColor.moodTired
        case .privacyProof:
            return OffRecordColor.moodGood
        case .faceID:
            return OffRecordColor.moodCalm
        case .relatable:
            return OffRecordColor.moodAnxious
        case .solution:
            return OffRecordColor.moodGreat
        case .preferences:
            return OffRecordColor.moodSad
        case .microphone:
            return OffRecordColor.moodAngry
        case .speech:
            return OffRecordColor.moodCalm
        case .processing:
            return OffRecordColor.moodOkay
        case .firstEntry:
            return OffRecordColor.moodCalm
        case .valueReveal:
            return OffRecordColor.moodGood
        case .habit:
            return OffRecordColor.moodTired
        case .finish:
            return OffRecordColor.moodGreat
        }
    }
}

struct OnboardingResponse: Codable, Equatable {
    var goal: OnboardingGoal?
    var painPoints: Set<OnboardingPainPoint> = []
    var relatableStatements: Set<RelatableStatement> = []
    var reflectionFocus: ReflectionFocus?
    var promptStyle: PromptStyle?
    var moodBaseline: MoodChoice = .calm
    var firstEntryText: String = ""
    var firstEntrySkipped: Bool = false
    var faceIDChoice: PermissionChoice = .notAsked
    var microphoneChoice: PermissionChoice = .notAsked
    var speechChoice: PermissionChoice = .notAsked
    var completedAt: Date?
}

struct OnboardingStore {
    private static let responseKey = "offrecord_onboarding_response"

    func save(_ response: OnboardingResponse) {
        guard let data = try? JSONEncoder().encode(response) else { return }
        UserDefaults.standard.set(data, forKey: Self.responseKey)
    }

    static func load() -> OnboardingResponse {
        guard let data = UserDefaults.standard.data(forKey: responseKey),
              let response = try? JSONDecoder().decode(OnboardingResponse.self, from: data) else {
            return OnboardingResponse()
        }
        return response
    }
}

enum PermissionChoice: String, Codable, Equatable {
    case notAsked
    case granted
    case denied
    case enabled
    case skipped
    case failed
}

private enum FirstEntryMode {
    case voice
    case textFallback
}

private enum OnboardingScrollTarget {
    static let welcomeNameField = "onboarding.welcome.nameField.anchor"
}

private enum OnboardingPalette {
    static let foreground = OffRecordColor.textBrand
    static let secondaryForeground = OffRecordColor.textBrand.opacity(0.74)
    static let tertiaryForeground = OffRecordColor.textBrand.opacity(0.54)
    static let surface = OffRecordColor.surfacePrimary
    static let surfaceSoft = OffRecordColor.surfacePrimary.opacity(0.56)
    static let surfaceSubtle = OffRecordColor.surfacePrimary.opacity(0.28)
    static let surfaceBarelyVisible = OffRecordColor.surfacePrimary.opacity(0.16)
    static let border = OffRecordColor.textBrand.opacity(0.14)
    static let selectedBorder = OffRecordColor.textBrand.opacity(0.28)
}

enum OnboardingGoal: String, CaseIterable, Codable, Identifiable {
    case moodPatterns
    case clearerThoughts
    case privateVenting
    case consistency
    case peopleTopics
    case fridayInsights

    var id: String { rawValue }

    var title: String {
        switch self {
        case .moodPatterns: return "Understand my mood patterns"
        case .clearerThoughts: return "Clear my head faster"
        case .privateVenting: return "Vent without worrying"
        case .consistency: return "Build a journaling habit"
        case .peopleTopics: return "See people and topics over time"
        case .fridayInsights: return "Let Friday notice patterns"
        }
    }

    var icon: String {
        switch self {
        case .moodPatterns: return "chart.line.uptrend.xyaxis"
        case .clearerThoughts: return "brain.head.profile"
        case .privateVenting: return "lock.shield.fill"
        case .consistency: return "flame.fill"
        case .peopleTopics: return "point.3.connected.trianglepath.dotted"
        case .fridayInsights: return "sparkles"
        }
    }
}

enum OnboardingPainPoint: String, CaseIterable, Codable, Identifiable {
    case typingSlow
    case detailsFade
    case privacyWorry
    case blankPage
    case manualMood
    case hardToSearch

    var id: String { rawValue }

    var title: String {
        switch self {
        case .typingSlow: return "Typing takes too long"
        case .detailsFade: return "Details fade before I write"
        case .privacyWorry: return "I worry where my thoughts go"
        case .blankPage: return "I do not know what to write"
        case .manualMood: return "Mood tracking feels manual"
        case .hardToSearch: return "Old entries are hard to search"
        }
    }

    var solutionTitle: String {
        switch self {
        case .typingSlow: return "Speak naturally and let OffRecord transcribe."
        case .detailsFade: return "Capture the honest version while it is fresh."
        case .privacyWorry: return "Local AI means Friday analysis stays on this device."
        case .blankPage: return "Private prompts make the first sentence easier."
        case .manualMood: return "Mood trends emerge from entries over time."
        case .hardToSearch: return "Friday connects people, topics, and themes."
        }
    }

    var icon: String {
        switch self {
        case .typingSlow: return "keyboard"
        case .detailsFade: return "timer"
        case .privacyWorry: return "lock"
        case .blankPage: return "doc.text.magnifyingglass"
        case .manualMood: return "heart.text.square"
        case .hardToSearch: return "magnifyingglass"
        }
    }
}

enum RelatableStatement: String, CaseIterable, Codable, Identifiable {
    case honestVersion
    case cloudConcern
    case patternWish
    case voiceEasier

    var id: String { rawValue }

    var title: String {
        switch self {
        case .honestVersion: return "I lose the honest version when I wait to write."
        case .cloudConcern: return "I avoid journaling when I think an app might upload it."
        case .patternWish: return "I want to see patterns without tagging everything manually."
        case .voiceEasier: return "I can say more in 30 seconds than I can type in minutes."
        }
    }
}

enum ReflectionFocus: String, CaseIterable, Codable, Identifiable {
    case emotions
    case relationships
    case decisions
    case growth

    var id: String { rawValue }

    var title: String {
        switch self {
        case .emotions: return "Emotions"
        case .relationships: return "People"
        case .decisions: return "Decisions"
        case .growth: return "Growth"
        }
    }

    var icon: String {
        switch self {
        case .emotions: return "heart.fill"
        case .relationships: return "person.2.fill"
        case .decisions: return "arrow.triangle.branch"
        case .growth: return "leaf.fill"
        }
    }
}

enum PromptStyle: String, CaseIterable, Codable, Identifiable {
    case gentle
    case direct
    case gratitude
    case evening

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gentle: return "Gentle check-ins"
        case .direct: return "Straight questions"
        case .gratitude: return "Gratitude prompts"
        case .evening: return "End-of-day recaps"
        }
    }
}

enum MoodChoice: String, CaseIterable, Codable, Identifiable {
    case calm
    case mixed
    case stretched
    case hopeful

    var id: String { rawValue }

    var title: String {
        switch self {
        case .calm: return "Calm"
        case .mixed: return "Mixed"
        case .stretched: return "Stretched"
        case .hopeful: return "Hopeful"
        }
    }

    var mood: Mood {
        switch self {
        case .calm: return .calm
        case .mixed: return .tired
        case .stretched: return .anxious
        case .hopeful: return .grateful
        }
    }
}

private struct ConcentricOnboardingPage<Content: View>: View {
    let isIPad: Bool
    let isKeyboardAdaptive: Bool
    let scrollTargetID: String?
    let content: Content
    @State private var isTextInputFocused = false

    init(
        isIPad: Bool,
        isKeyboardAdaptive: Bool = false,
        scrollTargetID: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.isIPad = isIPad
        self.isKeyboardAdaptive = isKeyboardAdaptive
        self.scrollTargetID = scrollTargetID
        self.content = content()
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollViewReader { scrollProxy in
                ScrollView(showsIndicators: false) {
                    VStack {
                        Spacer(minLength: 0)

                        content
                            .frame(maxWidth: isIPad ? 620 : .infinity)

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: minContentHeight(for: proxy.size.height))
                    .padding(.horizontal, isIPad ? 44 : 24)
                    .padding(.top, contentTopPadding)
                    .padding(.bottom, contentBottomPadding)
                }
                .animation(.easeInOut(duration: 0.25), value: isTextInputFocused)
                .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)) { _ in
                    guard isKeyboardAdaptive else { return }
                    isTextInputFocused = true
                }
                .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidEndEditingNotification)) { _ in
                    guard isKeyboardAdaptive else { return }
                    isTextInputFocused = false
                }
                .onChange(of: isTextInputFocused) { _, isFocused in
                    guard isKeyboardAdaptive, isFocused, let scrollTargetID else { return }
                    DispatchQueue.main.async {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            scrollProxy.scrollTo(scrollTargetID, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private var contentTopPadding: CGFloat {
        isFocusActive ? (isIPad ? 132 : 112) : 220
    }

    private var contentBottomPadding: CGFloat {
        let baseBottomPadding: CGFloat = 150
        guard isFocusActive else { return baseBottomPadding }
        return baseBottomPadding + (isIPad ? 260 : 320)
    }

    private func minContentHeight(for availableHeight: CGFloat) -> CGFloat {
        if isFocusActive {
            return max(availableHeight - 120, 420)
        }
        return max(availableHeight - 280, 520)
    }

    private var isFocusActive: Bool {
        isKeyboardAdaptive && isTextInputFocused
    }
}

// MARK: - Steps

private struct WelcomeStep: View {
    @Binding var nameDraft: String

    var body: some View {
        VStack(alignment: .center, spacing: 26) {
            ZStack {
                Circle()
                    .fill(OnboardingPalette.surfaceSubtle)
                    .frame(width: 148, height: 148)
                FridayMascotView(pose: .wave, size: 104)
            }

            Text("Speak freely. OffRecord turns your voice into insights using local AI on your device, even without internet.")
                .font(OffRecordTypography.titleSmall)
                .foregroundStyle(OnboardingPalette.secondaryForeground)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            OnboardingNameField(text: $nameDraft)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .id(OnboardingScrollTarget.welcomeNameField)
        }
    }
}

private struct OnboardingNameField: UIViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> UITextField {
        let textField = InsetTextField(frame: .zero)
        textField.delegate = context.coordinator
        textField.text = text
        textField.placeholder = "Your name (optional)"
        textField.textColor = UIColor(OffRecordColor.textPrimary)
        textField.tintColor = UIColor(OffRecordColor.textCoral)
        textField.font = UIFont.preferredFont(forTextStyle: .headline)
        textField.textContentType = .givenName
        textField.autocapitalizationType = .words
        textField.autocorrectionType = .no
        textField.returnKeyType = .done
        textField.clearButtonMode = .whileEditing
        textField.adjustsFontForContentSizeCategory = true
        textField.borderStyle = .none
        textField.backgroundColor = UIColor(OffRecordColor.surfacePrimary)
        textField.layer.cornerRadius = 14
        textField.layer.masksToBounds = true
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textField.accessibilityIdentifier = "onboarding.welcome.nameField"
        textField.addTarget(context.coordinator, action: #selector(Coordinator.textDidChange(_:)), for: .editingChanged)
        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextField, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 0, height: 56)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding private var text: String

        init(text: Binding<String>) {
            self._text = text
        }

        @objc func textDidChange(_ textField: UITextField) {
            text = textField.text ?? ""
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }
}

private final class InsetTextField: UITextField {
    private let contentInsets = UIEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 56)
    }

    override func textRect(forBounds bounds: CGRect) -> CGRect {
        bounds.inset(by: contentInsets)
    }

    override func editingRect(forBounds bounds: CGRect) -> CGRect {
        bounds.inset(by: contentInsets)
    }

    override func placeholderRect(forBounds bounds: CGRect) -> CGRect {
        bounds.inset(by: contentInsets)
    }

    override func clearButtonRect(forBounds bounds: CGRect) -> CGRect {
        super.clearButtonRect(forBounds: bounds).offsetBy(dx: -contentInsets.right / 2, dy: 0)
    }
}

private struct GoalStep: View {
    @Binding var selectedGoal: OnboardingGoal?

    var body: some View {
        OnboardingQuestion(
            eyebrow: "Your goal",
            title: "What do you want your journal to help with?",
            subtitle: "Pick the outcome that would make OffRecord worth opening every day."
        ) {
            VStack(spacing: 10) {
                ForEach(OnboardingGoal.allCases) { goal in
                    ChoiceRow(
                        title: goal.title,
                        icon: goal.icon,
                        isSelected: selectedGoal == goal
                    ) {
                        selectedGoal = goal
                    }
                }
            }
        }
    }
}

private struct PainPointsStep: View {
    @Binding var selectedPainPoints: Set<OnboardingPainPoint>

    var body: some View {
        OnboardingQuestion(
            eyebrow: "What gets in the way",
            title: "What usually stops you from journaling honestly?",
            subtitle: "Choose all that feel true. OffRecord will shape your starter experience around them."
        ) {
            VStack(spacing: 10) {
                ForEach(OnboardingPainPoint.allCases) { pain in
                    ChoiceRow(
                        title: pain.title,
                        icon: pain.icon,
                        isSelected: selectedPainPoints.contains(pain),
                        style: .checkbox
                    ) {
                        if selectedPainPoints.contains(pain) {
                            selectedPainPoints.remove(pain)
                        } else {
                            selectedPainPoints.insert(pain)
                        }
                    }
                }
            }
        }
    }
}

private struct PrivacyProofStep: View {
    var body: some View {
        OnboardingQuestion(
            eyebrow: "Privacy proof",
            title: "Local by design. Clear when Apple Speech is used.",
            subtitle: "Your journal is stored on your iPhone. Friday insights, mood analysis, Semantic Memory, and your private graph use on-device Apple frameworks."
        ) {
            VStack(spacing: 12) {
                PrivacyComparisonRow(label: "Journal text", offRecord: "On device", other: "Often uploaded")
                PrivacyComparisonRow(label: "Voice transcription", offRecord: "Apple Speech", other: "Cloud AI")
                PrivacyComparisonRow(label: "AI insights", offRecord: "Local AI", other: "Cloud AI")
                PrivacyComparisonRow(label: "Account", offRecord: "Not needed", other: "Usually required")
                PrivacyComparisonRow(label: "Analytics", offRecord: "None", other: "Common")
                PrivacyComparisonRow(label: "Offline use", offRecord: "Core app works", other: "Often limited")
            }
        }
    }
}

private struct FaceIDStep: View {
    let biometryName: String
    let isEnabled: Bool
    let isAvailable: Bool

    var body: some View {
        OnboardingQuestion(
            eyebrow: "Privacy lock",
            title: "Protect your journal before you write.",
            subtitle: "OffRecord can lock when you leave the app. iOS handles \(biometryName); OffRecord never sees or stores your biometrics."
        ) {
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(OffRecordColor.backgroundSageTint.opacity(0.28))
                        .frame(width: 132, height: 132)
                    Image(systemName: isEnabled ? "checkmark.shield.fill" : "faceid")
                        .font(.system(size: 54, weight: .semibold))
                        .foregroundStyle(OnboardingPalette.foreground)
                }

                VStack(alignment: .leading, spacing: 12) {
                    BenefitRow(icon: "lock.fill", text: "Require \(biometryName) or device passcode to open OffRecord.")
                    BenefitRow(icon: "iphone", text: "Lock automatically when the app goes to the background.")
                    BenefitRow(icon: "eye.slash.fill", text: "Keep private entries away from anyone holding your phone.")
                }

                if !isAvailable {
                    Text("Biometrics are unavailable on this device, so iOS will use your passcode.")
                        .font(OffRecordTypography.metadata)
                        .foregroundStyle(OnboardingPalette.secondaryForeground)
                        .padding()
                        .background(OnboardingPalette.surfaceSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
    }
}

private struct RelatableStep: View {
    @Binding var selectedStatements: Set<RelatableStatement>

    var body: some View {
        OnboardingQuestion(
            eyebrow: "A quick check",
            title: "Which statements sound like you?",
            subtitle: "Tap any that feel true. This helps Friday understand what matters first."
        ) {
            VStack(spacing: 12) {
                ForEach(RelatableStatement.allCases) { statement in
                    StatementCard(
                        statement: statement.title,
                        isSelected: selectedStatements.contains(statement)
                    ) {
                        if selectedStatements.contains(statement) {
                            selectedStatements.remove(statement)
                        } else {
                            selectedStatements.insert(statement)
                        }
                    }
                }
            }
        }
    }
}

private struct PersonalizedSolutionStep: View {
    let response: OnboardingResponse

    private var rows: [OnboardingPainPoint] {
        let selected = Array(response.painPoints).prefix(4)
        return selected.isEmpty ? Array(OnboardingPainPoint.allCases.prefix(4)) : Array(selected)
    }

    var body: some View {
        OnboardingQuestion(
            eyebrow: "Your private setup",
            title: "A smarter way to reflect, built around you.",
            subtitle: "Everything below runs locally. No internet connection, account, analytics, or third-party AI server is needed."
        ) {
            VStack(spacing: 12) {
                ForEach(rows) { pain in
                    SolutionRow(pain: pain)
                }
            }
        }
    }
}

private struct PreferencesStep: View {
    @Binding var response: OnboardingResponse

    var body: some View {
        OnboardingQuestion(
            eyebrow: "Make it yours",
            title: "What should Friday pay attention to first?",
            subtitle: "These choices shape your starter snapshot and first prompts."
        ) {
            VStack(alignment: .leading, spacing: 22) {
                PreferencePicker(
                    title: "Reflection focus",
                    items: ReflectionFocus.allCases,
                    selection: $response.reflectionFocus
                ) { item in
                    Label(item.title, systemImage: item.icon)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("How you feel lately")
                        .font(OffRecordTypography.sectionTitle)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(MoodChoice.allCases) { item in
                            Button {
                                response.moodBaseline = item
                            } label: {
                                Text(item.title)
                                    .font(OffRecordTypography.labelMedium)
                                    .foregroundStyle(OnboardingPalette.foreground)
                                    .frame(maxWidth: .infinity, minHeight: 46)
                                    .padding(.horizontal, 10)
                                    .background(response.moodBaseline == item ? OnboardingPalette.surface : OnboardingPalette.surfaceSubtle)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                PreferencePicker(
                    title: "Prompt style",
                    items: PromptStyle.allCases,
                    selection: $response.promptStyle
                ) { item in
                    Text(item.title)
                }
            }
        }
    }
}

private struct PermissionPrimerStep: View {
    let icon: String
    let title: String
    let subtitle: String
    let bullets: [String]

    var body: some View {
        OnboardingQuestion(
            eyebrow: "Before your first entry",
            title: title,
            subtitle: subtitle
        ) {
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(OnboardingPalette.surfaceSubtle)
                        .frame(width: 128, height: 128)
                    Image(systemName: icon)
                        .font(.system(size: 48, weight: .semibold))
                        .foregroundStyle(OnboardingPalette.foreground)
                }

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(bullets, id: \.self) { bullet in
                        BenefitRow(icon: "checkmark.circle.fill", text: bullet)
                    }
                }
            }
        }
    }
}

private struct ProcessingStep: View {
    @State private var animate = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 80)
            ZStack {
                Circle()
                    .stroke(OnboardingPalette.surfaceBarelyVisible, lineWidth: 18)
                    .frame(width: 150, height: 150)
                Circle()
                    .trim(from: 0.1, to: 0.82)
                    .stroke(OnboardingPalette.foreground, style: StrokeStyle(lineWidth: 18, lineCap: .round))
                    .frame(width: 150, height: 150)
                    .rotationEffect(.degrees(animate ? 360 : 0))
                    .animation(.linear(duration: 1.1).repeatForever(autoreverses: false), value: animate)
                Image(systemName: "sparkles")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(OnboardingPalette.foreground)
            }

            VStack(spacing: 10) {
                Text("No account lookup. Local AI is preparing your first reflection.")
                    .font(OffRecordTypography.labelMedium)
                    .foregroundStyle(OnboardingPalette.secondaryForeground)
                    .multilineTextAlignment(.center)
            }
            Spacer(minLength: 80)
        }
        .onAppear { animate = true }
    }
}

private struct FirstEntryStep: View {
    @ObservedObject var recorder: AudioRecorder
    let isRecording: Bool
    let isTranscribing: Bool
    let elapsedTime: TimeInterval
    let level: Float
    @Binding var draft: String
    @Binding var selectedMood: Mood
    let mode: FirstEntryMode
    let entryCreated: Bool
    let onRecordTap: () -> Void

    @FocusState private var isTextEditorFocused: Bool

    var body: some View {
        OnboardingQuestion(
            eyebrow: "First entry",
            title: "Say one honest thing about today.",
            subtitle: mode == .voice
                ? "Record 20 to 30 seconds. This becomes your first real OffRecord entry."
                : "Type one honest thing. This becomes your first real OffRecord entry."
        ) {
            VStack(spacing: 18) {
                switch mode {
                case .voice:
                    voiceRecorder
                case .textFallback:
                    textFallbackEditor
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Add a starting mood")
                        .font(OffRecordTypography.sectionTitle)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(Mood.selectableMoods.prefix(6)) { mood in
                            Button {
                                selectedMood = mood
                            } label: {
                                HStack {
                                    MiniMoodIcon(
                                        mood: mood,
                                        size: 20,
                                        opacity: selectedMood == mood ? 0.92 : 0.72
                                    )
                                    Text(mood.displayName)
                                    Spacer()
                                }
                                .font(OffRecordTypography.labelMedium)
                                .padding(12)
                                .foregroundStyle(selectedMood == mood ? mood.readableStyle.foreground : OnboardingPalette.foreground)
                                .background(selectedMood == mood ? mood.color : OnboardingPalette.surfaceSubtle)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .onAppear {
            focusTextEditorIfNeeded()
        }
        .onChange(of: mode) { _, _ in
            focusTextEditorIfNeeded()
        }
    }

    private var voiceRecorder: some View {
        Button(action: onRecordTap) {
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(isRecording ? OffRecordColor.textCoral : OnboardingPalette.surface)
                        .frame(width: 104, height: 104)
                    Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 38, weight: .bold))
                        .foregroundStyle(isRecording ? OffRecordColor.textInverse : OffRecordColor.textAqua)
                }

                if isRecording {
                    Text(formatTime(elapsedTime))
                        .font(OffRecordTypography.numberMedium)
                    WaveformMeter(level: level)
                    Text("Tap to stop")
                        .font(OffRecordTypography.labelMedium)
                        .foregroundStyle(OnboardingPalette.secondaryForeground)
                } else if isTranscribing {
                    ProgressView("Transcribing on this device...")
                        .tint(OnboardingPalette.foreground)
                        .foregroundStyle(OnboardingPalette.foreground)
                } else if entryCreated {
                    Label("First entry saved", systemImage: "checkmark.circle.fill")
                        .font(OffRecordTypography.sectionTitle)
                        .foregroundStyle(OnboardingPalette.foreground)
                } else {
                    Text("Tap to record privately")
                        .font(OffRecordTypography.sectionTitle)
                    Text("Your recording is stored locally.")
                        .font(OffRecordTypography.labelSmall)
                        .foregroundStyle(OnboardingPalette.secondaryForeground)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .background(OnboardingPalette.surfaceSubtle)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isTranscribing)
    }

    private var textFallbackEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Type your first entry")
                .font(OffRecordTypography.sectionTitle)
            TextField("Write your first entry...", text: $draft, axis: .vertical)
                .focused($isTextEditorFocused)
                .foregroundColor(OffRecordColor.textPrimary)
                .lineLimit(6...10)
                .frame(minHeight: 160)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(14)
                .background(OnboardingPalette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .onAppear {
            focusTextEditorIfNeeded()
        }
    }

    private func focusTextEditorIfNeeded() {
        guard mode == .textFallback else {
            isTextEditorFocused = false
            return
        }

        [0.1, 0.45, 0.8].forEach { delay in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                isTextEditorFocused = true
            }
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private struct ValueRevealStep: View {
    let response: OnboardingResponse
    let entryText: String
    let mood: Mood

    var body: some View {
        OnboardingQuestion(
            eyebrow: "Your starter snapshot",
            title: "Friday has enough to start listening for patterns.",
            subtitle: "This preview was generated from your onboarding choices and first reflection. Future insights stay local too."
        ) {
            VStack(spacing: 14) {
                StarterSnapshotCard(response: response, entryText: entryText, mood: mood)
                TopicGraphCard(response: response, entryText: entryText)
            }
        }
    }
}

private struct HabitSetupStep: View {
    @ObservedObject var reminderManager: ReminderManager
    @ObservedObject var goalManager: GoalManager
    let onReminderDenied: () -> Void

    var body: some View {
        OnboardingQuestion(
            eyebrow: "Build the habit",
            title: "Make reflection easy to repeat.",
            subtitle: "Optional reminders and weekly goals stay in iOS and OffRecord settings. The app still works fully offline."
        ) {
            VStack(spacing: 16) {
                Toggle(isOn: Binding(
                    get: { reminderManager.isEnabled },
                    set: { newValue in
                        if newValue {
                            reminderManager.requestPermissionIfNeeded { granted in
                                if granted {
                                    reminderManager.isEnabled = true
                                } else {
                                    reminderManager.isEnabled = false
                                    onReminderDenied()
                                }
                            }
                        } else {
                            reminderManager.isEnabled = false
                        }
                    }
                )) {
                    Label("Remind me once a day", systemImage: "bell.badge.fill")
                }
                .tint(OffRecordColor.textBrand)
                .padding()
                .background(OnboardingPalette.surfaceSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                if reminderManager.isEnabled {
                    DatePicker(
                        "Reminder time",
                        selection: Binding(
                            get: { reminderManager.reminderTime },
                            set: { reminderManager.reminderTime = $0 }
                        ),
                        displayedComponents: .hourAndMinute
                    )
                    .padding()
                    .background(OnboardingPalette.surfaceSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                Toggle(isOn: $goalManager.isEnabled) {
                    Label("Set a weekly journaling goal", systemImage: "flame.fill")
                }
                .tint(.orange)
                .padding()
                .background(OnboardingPalette.surfaceSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                if goalManager.isEnabled {
                    Stepper("Target: \(goalManager.weeklyTarget) entries/week", value: $goalManager.weeklyTarget, in: 1...7)
                        .padding()
                        .background(OnboardingPalette.surfaceSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
    }
}

private struct FinishStep: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 80)
            ZStack {
                Circle()
                    .fill(OnboardingPalette.surfaceSubtle)
                    .frame(width: 150, height: 150)
                FridayMascotView(pose: .wave, size: 104)
            }

            VStack(spacing: 12) {
                Text("Record, reflect, and let Friday notice patterns entirely on this device. No internet connection required for the core experience.")
                    .font(OffRecordTypography.titleSmall)
                    .foregroundStyle(OnboardingPalette.secondaryForeground)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            Spacer(minLength: 80)
        }
    }
}

// MARK: - Components

private struct OnboardingProgressHeader: View {
    let step: OnboardingStep
    let canGoBack: Bool
    let onBack: () -> Void
    private let sideWidth: CGFloat = 54

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 0) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(OffRecordTypography.sectionTitle)
                        .frame(width: 36, height: 36)
                        .background(canGoBack ? OnboardingPalette.surfaceSubtle : OnboardingPalette.surfaceBarelyVisible)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canGoBack)
                .opacity(canGoBack ? 1 : 0)
                .frame(width: sideWidth, alignment: .leading)

                headerCenterContent
                    .frame(maxWidth: .infinity)

                Text(step.progressText)
                    .font(OffRecordTypography.badgeLabel)
                    .foregroundStyle(OnboardingPalette.secondaryForeground)
                    .frame(width: sideWidth, alignment: .trailing)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.black.opacity(0.14))
                    Capsule()
                        .fill(OnboardingPalette.foreground)
                        .frame(width: max(8, proxy.size.width * step.progress))
                }
            }
            .frame(height: 6)
        }
    }

    @ViewBuilder
    private var headerCenterContent: some View {
        Text(step.pageTitle.uppercased())
            .font(OffRecordTypography.screenTitle)
            .foregroundStyle(OnboardingPalette.foreground)
            .lineLimit(3)
            .minimumScaleFactor(0.58)
            .allowsTightening(true)
            .multilineTextAlignment(.center)
    }
}

private struct OnboardingBottomBar: View {
    let primaryTitle: String
    let primaryIcon: String?
    let secondaryTitle: String?
    let isPrimaryDisabled: Bool
    let onPrimary: () -> Void
    let onSecondary: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Button(action: onPrimary) {
                HStack(spacing: 8) {
                    Text(primaryTitle)
                    if let primaryIcon {
                        Image(systemName: primaryIcon)
                    }
                }
                .font(OffRecordTypography.sectionTitle)
                .foregroundStyle(OffRecordColor.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(isPrimaryDisabled ? OnboardingPalette.surfaceSoft : OnboardingPalette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isPrimaryDisabled)

            if let secondaryTitle {
                Button(secondaryTitle, action: onSecondary)
                    .font(OffRecordTypography.labelMedium)
                    .foregroundStyle(OnboardingPalette.secondaryForeground)
                    .buttonStyle(.plain)
            }
        }
        .padding(.top, 16)
        .background(
            LinearGradient(
                colors: [.clear, OnboardingPalette.surfaceSoft],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }
}

private struct OnboardingQuestion<Content: View>: View {
    let subtitle: String
    let content: Content

    init(
        eyebrow _: String,
        title _: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) {
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .center, spacing: 24) {
            Text(subtitle)
                .font(OffRecordTypography.labelMedium)
                .foregroundStyle(OnboardingPalette.secondaryForeground)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            content
                .frame(maxWidth: .infinity)
        }
    }
}

private enum ChoiceRowStyle {
    case radio
    case checkbox
}

private struct ChoiceRow: View {
    let title: String
    let icon: String
    let isSelected: Bool
    var style: ChoiceRowStyle = .radio
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(OffRecordTypography.sectionTitle)
                    .frame(width: 34, height: 34)
                    .foregroundStyle(OnboardingPalette.foreground)
                    .background(isSelected ? OnboardingPalette.surface : OnboardingPalette.surfaceSubtle)
                    .clipShape(Circle())

                Text(title)
                    .font(OffRecordTypography.sectionTitle)
                    .foregroundStyle(OnboardingPalette.foreground)
                    .lineLimit(2)
                    .minimumScaleFactor(0.86)
                    .multilineTextAlignment(.leading)
                    .layoutPriority(1)

                Spacer()

                Image(systemName: selectedIconName)
                    .font(OffRecordTypography.sectionTitle)
                    .foregroundStyle(isSelected ? OnboardingPalette.foreground : OnboardingPalette.tertiaryForeground)
            }
            .padding(14)
            .background(isSelected ? OnboardingPalette.surfaceSoft : OnboardingPalette.surfaceSubtle)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? OnboardingPalette.selectedBorder : OnboardingPalette.border, lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var selectedIconName: String {
        switch style {
        case .radio:
            return isSelected ? "checkmark.circle.fill" : "circle"
        case .checkbox:
            return isSelected ? "checkmark.square.fill" : "square"
        }
    }
}

private struct StatementCard: View {
    let statement: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "quote.opening")
                    .font(OffRecordTypography.titleSmall)
                    .foregroundStyle(OnboardingPalette.foreground)
                Text(statement)
                    .font(OffRecordTypography.titleSmall)
                    .lineSpacing(3)
                Spacer()
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? OnboardingPalette.surfaceSoft : OnboardingPalette.surfaceSubtle)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(isSelected ? OnboardingPalette.selectedBorder : OnboardingPalette.border, lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct PrivacyComparisonRow: View {
    let label: String
    let offRecord: String
    let other: String

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(OffRecordTypography.labelMedium)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(offRecord)
                .font(OffRecordTypography.labelSmall)
                .foregroundStyle(OffRecordColor.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(OnboardingPalette.surface)
                .clipShape(Capsule())

            Text(other)
                .font(OffRecordTypography.labelSmall)
                .foregroundStyle(OnboardingPalette.secondaryForeground)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(OnboardingPalette.surfaceSubtle)
                .clipShape(Capsule())
        }
        .padding(14)
        .background(OnboardingPalette.surfaceBarelyVisible)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct SolutionRow: View {
    let pain: OnboardingPainPoint

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: pain.icon)
                .font(OffRecordTypography.sectionTitle)
                .foregroundStyle(OnboardingPalette.foreground)
                .frame(width: 34, height: 34)
                .background(OnboardingPalette.surfaceSubtle)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(pain.title)
                    .font(OffRecordTypography.labelSmall)
                    .foregroundStyle(OnboardingPalette.secondaryForeground)
                Text(pain.solutionTitle)
                    .font(OffRecordTypography.sectionTitle)
                    .foregroundStyle(OnboardingPalette.foreground)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OnboardingPalette.surfaceBarelyVisible)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct BenefitRow: View {
    let icon: String?
    let mood: Mood?
    let text: String

    init(icon: String, text: String) {
        self.icon = icon
        self.mood = nil
        self.text = text
    }

    init(mood: Mood, text: String) {
        self.icon = nil
        self.mood = mood
        self.text = text
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let mood {
                MiniMoodIcon(mood: mood, size: 18, opacity: 0.88)
                    .frame(width: 22)
            } else if let icon {
                Image(systemName: icon)
                    .font(OffRecordTypography.labelMedium)
                    .foregroundStyle(OnboardingPalette.foreground)
                    .frame(width: 22)
            }
            Text(text)
                .font(OffRecordTypography.labelMedium)
                .foregroundStyle(OnboardingPalette.secondaryForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct PreferencePicker<Item: Identifiable & Equatable, Label: View>: View {
    let title: String
    let items: [Item]
    @Binding var selection: Item?
    let label: (Item) -> Label

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(OffRecordTypography.sectionTitle)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(items) { item in
                    Button {
                        selection = item
                    } label: {
                        label(item)
                            .font(OffRecordTypography.labelMedium)
                            .foregroundStyle(OnboardingPalette.foreground)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .padding(.horizontal, 10)
                            .background(selection == item ? OnboardingPalette.surface : OnboardingPalette.surfaceSubtle)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct LocalAIBadge: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "cpu.fill")
            Text("Local AI")
            Circle().fill(OnboardingPalette.tertiaryForeground).frame(width: 4, height: 4)
            Text("Core works offline")
        }
        .font(OffRecordTypography.labelSmall)
        .foregroundStyle(OffRecordColor.textPrimary)
        .lineLimit(1)
        .minimumScaleFactor(0.78)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(OnboardingPalette.surface)
        .clipShape(Capsule())
    }
}

private struct JournalPreviewCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Today", systemImage: "mic.fill")
                    .font(OffRecordTypography.sectionTitle)
                Spacer()
                OfflineIndicator()
            }

            Text("I finally said the thing I kept editing in my head...")
                .font(OffRecordTypography.titleSmall)
                .lineSpacing(3)

            HStack(spacing: 10) {
                PreviewPill(icon: "heart.fill", text: "Calm")
                PreviewPill(icon: "person.2.fill", text: "People")
                PreviewPill(icon: "sparkles", text: "Friday")
            }
        }
        .padding(18)
        .background(OnboardingPalette.surfaceSubtle)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(OnboardingPalette.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct PreviewPill: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(OffRecordTypography.labelSmall)
            .foregroundStyle(OnboardingPalette.secondaryForeground)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(OnboardingPalette.surfaceSubtle)
            .clipShape(Capsule())
    }
}

private struct WaveformMeter: View {
    let level: Float

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<18, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(OnboardingPalette.foreground)
                    .frame(width: 4, height: barHeight(index))
                    .opacity(indexOpacity(index))
            }
        }
        .frame(height: 34)
    }

    private func barHeight(_ index: Int) -> CGFloat {
        let normalized = CGFloat(max(0.12, min(1, level)))
        let wave = CGFloat(sin(Double(index) * 0.55 + Date().timeIntervalSince1970 * 7) * 0.28 + 0.72)
        return 8 + normalized * wave * 24
    }

    private func indexOpacity(_ index: Int) -> Double {
        let threshold = Double(index) / 18.0
        return Double(level) > threshold ? 1 : 0.35
    }
}

private struct StarterSnapshotCard: View {
    let response: OnboardingResponse
    let entryText: String
    let mood: Mood

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Friday Starter Snapshot", systemImage: "sparkles")
                .font(OffRecordTypography.sectionTitle)
                .foregroundStyle(OnboardingPalette.foreground)

            Text(snapshotText)
                .font(OffRecordTypography.titleSmall)
                .lineSpacing(4)

            VStack(alignment: .leading, spacing: 10) {
                BenefitRow(mood: mood, text: "Starting mood: \(mood.displayName)")
                BenefitRow(icon: "lock.shield.fill", text: "This insight was prepared locally on your device.")
                BenefitRow(icon: "wifi.slash", text: "No internet connection is required for core journaling.")
            }
        }
        .padding(18)
        .background(OnboardingPalette.surfaceSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var snapshotText: String {
        let goal = response.goal?.title ?? "reflect more clearly"
        let focus = response.reflectionFocus?.title.lowercased() ?? "patterns"
        if entryText.trimmed.isEmpty {
            return "You want to \(goal.lowercased()). Friday will start by watching for \(focus) across your entries."
        }
        return "You want to \(goal.lowercased()). From your first entry, Friday will start watching for \(focus) while keeping everything private."
    }
}

private struct TopicGraphCard: View {
    let response: OnboardingResponse
    let entryText: String

    private var nodes: [String] {
        var values = [
            response.reflectionFocus?.title ?? "Reflection",
            response.goal?.title.components(separatedBy: " ").suffix(2).joined(separator: " ") ?? "Patterns",
            response.promptStyle?.title ?? "Prompts"
        ]

        let words = entryText
            .split { !$0.isLetter }
            .map(String.init)
            .filter { $0.count > 4 }
            .prefix(2)
        values.append(contentsOf: words)
        return Array(values.prefix(5))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Sample People and Topics Graph", systemImage: "point.3.connected.trianglepath.dotted")
                .font(OffRecordTypography.sectionTitle)
                .foregroundStyle(OnboardingPalette.foreground)

            ZStack {
                ForEach(Array(nodes.enumerated()), id: \.offset) { index, node in
                    TopicNode(title: node, index: index)
                }
            }
            .frame(height: 210)
            .frame(maxWidth: .infinity)

            Text("As you journal, OffRecord connects recurring people, places, moods, and themes locally. This graph stays on this device.")
                .font(OffRecordTypography.labelMedium)
                .foregroundStyle(OnboardingPalette.secondaryForeground)
        }
        .padding(18)
        .background(OnboardingPalette.surfaceSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct TopicNode: View {
    let title: String
    let index: Int

    private var position: CGPoint {
        switch index {
        case 0: return CGPoint(x: 0.50, y: 0.18)
        case 1: return CGPoint(x: 0.22, y: 0.50)
        case 2: return CGPoint(x: 0.76, y: 0.48)
        case 3: return CGPoint(x: 0.36, y: 0.82)
        default: return CGPoint(x: 0.66, y: 0.78)
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if index != 0 {
                    Path { path in
                        path.move(to: CGPoint(x: proxy.size.width * 0.50, y: proxy.size.height * 0.18))
                        path.addLine(to: CGPoint(x: proxy.size.width * position.x, y: proxy.size.height * position.y))
                    }
                    .stroke(OnboardingPalette.tertiaryForeground, lineWidth: 2)
                }

                Text(title)
                    .font(OffRecordTypography.labelSmall)
                    .foregroundStyle(OnboardingPalette.foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(index == 0 ? OnboardingPalette.surface : OnboardingPalette.surfaceSubtle)
                    .clipShape(Capsule())
                    .position(x: proxy.size.width * position.x, y: proxy.size.height * position.y)
            }
        }
    }
}

// MARK: - Privacy Badge Component

struct PrivacyBadge: View {
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.shield.fill")
                .font(compact ? OffRecordTypography.annotation : OffRecordTypography.bodySmall)
                .foregroundColor(OffRecordColor.textSage)

            if !compact {
                Text("100% Private")
                    .font(OffRecordTypography.labelSmall)
                    .foregroundColor(OffRecordColor.textSage)
            }
        }
        .padding(.horizontal, compact ? 8 : 12)
        .padding(.vertical, compact ? 4 : 6)
        .background(OffRecordColor.backgroundSageTint)
        .overlay(Capsule().stroke(OffRecordColor.borderSage, lineWidth: 1))
        .clipShape(Capsule())
    }
}

// MARK: - Offline Indicator

struct OfflineIndicator: View {
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(OffRecordColor.brandSageDark)
                .frame(width: 6, height: 6)
            Text("Offline")
                .font(OffRecordTypography.labelSmall)
                .foregroundColor(OffRecordColor.textSage)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(OffRecordColor.backgroundSageTint)
        .overlay(Capsule().stroke(OffRecordColor.borderSage, lineWidth: 1))
        .clipShape(Capsule())
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#Preview {
    OnboardingView(hasCompletedOnboarding: .constant(false))
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
