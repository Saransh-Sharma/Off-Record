//
//  OnboardingView.swift
//  OffRecord
//
//  Questionnaire-style first launch experience.
//

import SwiftUI
import TranscriptionKit
import CoreData
import AVFoundation
import os.log
#if canImport(UIKit)
import UIKit
#endif

private let onboardingLogger = Logger(subsystem: "com.singularity.offrecord", category: "Onboarding")

private struct PendingOnboardingTranscription {
    let entryObjectID: NSManagedObjectID
    let attachmentObjectID: NSManagedObjectID
    let audioURL: URL
}

private final class OnboardingTransitionGate: ObservableObject {
    @Published var isLocked = false
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
    @StateObject private var transitionGate = OnboardingTransitionGate()

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
    @State private var isWelcomeNameFieldFocused = false
    @State private var isFirstReflectionTextFocused = false

    private var isIPad: Bool { horizontalSizeClass == .regular }
    private var onboardingTransitionDuration: Double { reduceMotion ? 0.01 : 0.7 }
    private var isWelcomeKeyboardLiftActive: Bool {
        step == .welcome && isWelcomeNameFieldFocused
    }

    var body: some View {
        ZStack {
            ConcentricPageTransitionView(
                pages: concentricPages,
                currentIndex: stepIndex,
                duration: onboardingTransitionDuration,
                ctaTitle: primaryTitle,
                ctaIcon: primaryIcon ?? "chevron.forward",
                isCTADisabled: isPrimaryDisabled || transitionGate.isLocked,
                secondaryTitle: secondaryTitle,
                playsPrimaryHaptic: step != .firstReflection,
                onPrimaryAction: primaryAction,
                onSecondaryAction: secondaryAction
            )
        }
        .foregroundStyle(OffRecordColor.textBrand)
        // The full-bleed pastel pages are light-only artwork; keep text and fields readable on them.
        .environment(\.colorScheme, .light)
        .onAppear {
            nameDraft = authorName
            firstEntryDraft = response.firstEntryText
            if response.microphoneChoice == .denied {
                firstEntryMode = .textFallback
            }
            configureForUITestingIfNeeded()
        }
        .onChange(of: response) { _, newValue in
            store.save(newValue)
        }
        .onChange(of: step) { _, newStep in
            if newStep != .welcome {
                isWelcomeNameFieldFocused = false
            }
            if newStep != .firstReflection {
                isFirstReflectionTextFocused = false
            }
        }
        .alert("Something Went Wrong", isPresented: Binding(
            get: { onboardingError != nil },
            set: { if !$0 { onboardingError = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(onboardingError ?? "")
        }
        .alert("Notifications Are Off", isPresented: $showNotificationDeniedAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("You can turn on reminders later in Settings.")
        }
        .alert(SpeechTranscriptionConsent.disclosureTitle, isPresented: $showSpeechConsentPrompt) {
            Button("Transcribe") {
                SpeechTranscriptionConsent.grantAppleSpeechProcessing()
                resumePendingTranscription()
            }
        } message: {
            Text(SpeechTranscriptionConsent.disclosureMessage)
        }
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
        OnboardingStep.allCases.map { pageStep in
            let scrollTargetID = onboardingScrollTargetID(for: pageStep)
            return (
                view: AnyView(
                    ConcentricOnboardingScreen(
                        step: pageStep,
                        isIPad: isIPad,
                        isHeaderCompact: isHeaderCompact(for: pageStep),
                        isHeaderLifted: isHeaderLifted(for: pageStep),
                        headerLiftOffset: headerKeyboardLiftOffset,
                        onBack: goBack
                    ) {
                        ConcentricOnboardingPage(
                            isIPad: isIPad,
                            isKeyboardAdaptive: scrollTargetID != nil,
                            scrollTargetID: scrollTargetID,
                            onTextInputFocusChange: textFocusHandler(for: pageStep)
                        ) {
                            currentStepContent(for: pageStep)
                        }
                    }
                ),
                background: pageStep.backgroundColor
            )
        }
    }

    private func isHeaderCompact(for pageStep: OnboardingStep) -> Bool {
        guard pageStep == step else { return false }
        switch pageStep {
        case .welcome:
            return isWelcomeNameFieldFocused
        case .firstReflection:
            return isFirstReflectionTextFocused
        default:
            return false
        }
    }

    private func isHeaderLifted(for pageStep: OnboardingStep) -> Bool {
        pageStep == .welcome && step == .welcome && isWelcomeNameFieldFocused
    }

    private func onboardingScrollTargetID(for step: OnboardingStep) -> String? {
        switch step {
        case .welcome:
            return OnboardingScrollTarget.welcomeNameField
        case .firstReflection:
            return OnboardingScrollTarget.firstEntryTextField
        default:
            return nil
        }
    }

    private func textFocusHandler(for step: OnboardingStep) -> ((Bool) -> Void)? {
        switch step {
        case .welcome:
            return { isWelcomeNameFieldFocused = $0 }
        case .firstReflection:
            return { isFirstReflectionTextFocused = $0 }
        default:
            return nil
        }
    }

    private var headerKeyboardLiftOffset: CGFloat {
        isIPad ? -12 : -8
    }

    @ViewBuilder
    private func currentStepContent(for step: OnboardingStep) -> some View {
        switch step {
        case .welcome:
            WelcomeStep(nameDraft: $nameDraft, isCompact: isWelcomeKeyboardLiftActive)
        case .intent:
            // Friday's reflection focus and prompt style keep their defaults.
            IntentStep(selectedIntents: $response.painPoints)
        case .privacy:
            PrivacyProofStep()
        case .lock:
            FaceIDStep(
                biometryName: lockManager.biometryTypeName,
                isEnabled: lockManager.isEnabled,
                isAvailable: lockManager.biometricsAvailable
            )
        case .firstReflection:
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
        case .habit:
            HabitSetupStep(
                reminderManager: reminderManager,
                goalManager: goalManager,
                onReminderDenied: { showNotificationDeniedAlert = true }
            )
        }
    }

    private var primaryTitle: String {
        switch step {
        case .welcome: return String(localized: "Continue")
        case .intent, .privacy: return String(localized: "Continue")
        case .lock: return lockManager.isEnabled ? String(localized: "Continue") : lockPrimaryTitle
        case .firstReflection: return firstReflectionPrimaryTitle
        case .habit: return String(localized: "Start Journaling")
        }
    }

    /// "Use Face ID", "Use Touch ID", "Use Optic ID", or "Use Passcode".
    private var lockPrimaryTitle: String {
        String(localized: "Use \(lockManager.biometryTypeName)")
    }

    private var firstReflectionPrimaryTitle: String {
        if isTranscribing { return String(localized: "Transcribing…") }
        if entryCreated { return String(localized: "Continue") }
        switch firstEntryMode {
        case .voice:
            return isRecording ? String(localized: "Stop Recording") : String(localized: "Record", comment: "Button that starts a voice recording")
        case .textFallback:
            return String(localized: "Save", comment: "Onboarding button that saves the typed first entry")
        }
    }

    private var primaryIcon: String? {
        switch step {
        case .welcome, .intent, .privacy, .habit:
            return "arrow.right"
        case .lock:
            return lockManager.isEnabled ? "arrow.right" : "lock.shield.fill"
        case .firstReflection:
            if isTranscribing { return "hourglass" }
            if entryCreated { return "arrow.right" }
            switch firstEntryMode {
            case .voice:
                return isRecording ? "stop.fill" : "mic.fill"
            case .textFallback:
                return "checkmark"
            }
        }
    }

    private var secondaryTitle: String? {
        switch step {
        case .lock:
            return lockManager.isEnabled ? nil : String(localized: "Not Now")
        case .firstReflection:
            return (isRecording || isTranscribing) ? nil : String(localized: "Skip", comment: "Button that skips an onboarding step")
        case .habit:
            return String(localized: "Skip", comment: "Button that skips an onboarding step")
        default:
            return nil
        }
    }

    private var isPrimaryDisabled: Bool {
        switch step {
        case .intent:
            return response.painPoints.isEmpty
        case .firstReflection:
            if isTranscribing { return true }
            if entryCreated { return false }
            switch firstEntryMode {
            case .voice:
                return false
            case .textFallback:
                return firstEntryDraft.trimmed.isEmpty
            }
        default:
            return false
        }
    }

    private func primaryAction() {
        guard !transitionGate.isLocked else { return }
        switch step {
        case .welcome:
            authorName = Personalization.trimmedName(from: nameDraft)
            goForward()
        case .lock:
            if lockManager.isEnabled {
                goForward()
            } else {
                enableFaceID()
            }
        case .firstReflection:
            if entryCreated {
                response.firstEntryText = firstEntryDraft.trimmed
                goForward()
            } else if firstEntryMode == .voice {
                toggleRecording()
            } else {
                saveTypedEntryIfNeeded()
            }
        case .habit:
            completeOnboarding()
        default:
            goForward()
        }
    }

    private func secondaryAction() {
        guard !transitionGate.isLocked else { return }
        switch step {
        case .lock:
            response.faceIDChoice = .skipped
            goForward()
        case .firstReflection:
            response.firstEntrySkipped = true
            goForward()
        case .habit:
            completeOnboarding()
        default:
            break
        }
    }

    private func goForward() {
        guard let next = step.next else { return }
        transition(to: next)
    }

    private func goBack() {
        guard let previous = step.previous else { return }
        transition(to: previous)
    }

    private func transition(to nextStep: OnboardingStep) {
        guard nextStep != step, !transitionGate.isLocked else { return }
        transitionGate.isLocked = true
        step = nextStep
        // Short guard against double taps; the page transition itself keeps running.
        DispatchQueue.main.asyncAfter(deadline: .now() + min(0.4, onboardingTransitionDuration + 0.05)) {
            transitionGate.isLocked = false
        }
    }

    private func enableFaceID() {
        lockManager.authenticate { success in
            if success {
                lockManager.isEnabled = true
                response.faceIDChoice = .enabled
                goForward()
            } else {
                response.faceIDChoice = .failed
                onboardingError = String(localized: "\(lockManager.biometryTypeName) wasn’t turned on. You can turn it on in Settings.")
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
                    onboardingError = String(localized: "Recording didn’t start. You can type instead.")
                    HapticManager.shared.error()
                }
            }
        }
        #else
        firstEntryMode = .textFallback
        onboardingError = String(localized: "Recording didn’t start. You can type instead.")
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
        let entry = createEntry(text: "", audioURL: result.url, duration: result.duration)
        entry.entryTranscriptionStatus = .processing
        try? viewContext.save()
        firstEntryAudioEntryID = entry.objectID
        let fileExists = FileManager.default.fileExists(atPath: result.url.path)
        let byteCount = ((try? FileManager.default.attributesOfItem(atPath: result.url.path)[.size]) as? NSNumber)?.int64Value ?? -1
        onboardingLogger.info("Onboarding audio saved entryID=\(entry.id?.uuidString ?? "missing", privacy: .public) duration=\(result.duration, privacy: .public) fileExists=\(fileExists, privacy: .public) bytes=\(byteCount, privacy: .public) transcriptionStatus=processing")

        guard let attachment = AudioAttachmentStore.audioAttachment(
            fileName: result.url.lastPathComponent,
            entry: entry,
            in: viewContext
        ) else {
            onboardingError = String(localized: "Recording saved. Transcription didn’t start.")
            isTranscribing = false
            return
        }
        beginTranscription(
            entryObjectID: entry.objectID,
            attachmentObjectID: attachment.objectID,
            audioURL: result.url
        )
    }

    private func beginTranscription(
        entryObjectID: NSManagedObjectID,
        attachmentObjectID: NSManagedObjectID,
        audioURL: URL
    ) {
        guard let entry = try? viewContext.existingObject(with: entryObjectID) as? DiaryEntry,
              let attachment = try? viewContext.existingObject(with: attachmentObjectID) else {
            isTranscribing = false
            return
        }
        guard SpeechTranscriptionConsent.hasGrantedAppleSpeechProcessing else {
            pendingTranscription = PendingOnboardingTranscription(
                entryObjectID: entryObjectID,
                attachmentObjectID: attachmentObjectID,
                audioURL: audioURL
            )
            attachment.setValue(AudioTranscriptionStatus.none.rawValue, forKey: "transcriptionStatus")
            entry.entryTranscriptionStatus = .none
            try? viewContext.save()
            onboardingLogger.info("Onboarding speech consent required entryID=\(entry.id?.uuidString ?? "missing", privacy: .public) transcriptionStatus=none")
            firstEntryMode = .textFallback
            isTranscribing = false
            showSpeechConsentPrompt = true
            return
        }

        transcribeFirstEntry(
            entryObjectID: entryObjectID,
            attachmentObjectID: attachmentObjectID,
            audioURL: audioURL
        )
    }

    private func resumePendingTranscription() {
        guard let pendingTranscription else {
            isTranscribing = false
            return
        }

        self.pendingTranscription = nil
        guard let entry = try? viewContext.existingObject(with: pendingTranscription.entryObjectID) as? DiaryEntry else {
            onboardingLogger.error("Unable to resume onboarding transcription because entry no longer exists")
            isTranscribing = false
            return
        }

        onboardingLogger.info("Resuming onboarding transcription entryID=\(entry.id?.uuidString ?? "missing", privacy: .public)")
        isTranscribing = true
        firstEntryMode = .voice
        transcribeFirstEntry(
            entryObjectID: entry.objectID,
            attachmentObjectID: pendingTranscription.attachmentObjectID,
            audioURL: pendingTranscription.audioURL
        )
    }

    private func transcribeFirstEntry(
        entryObjectID: NSManagedObjectID,
        attachmentObjectID: NSManagedObjectID,
        audioURL: URL
    ) {
        guard let entry = try? viewContext.existingObject(with: entryObjectID) as? DiaryEntry,
              let attachment = try? viewContext.existingObject(with: attachmentObjectID) else {
            isTranscribing = false
            return
        }
        isTranscribing = true
        AudioAttachmentStore.markTranscriptionProcessing(attachment)
        try? viewContext.save()
        let fileExists = FileManager.default.fileExists(atPath: audioURL.path)
        let byteCount = ((try? FileManager.default.attributesOfItem(atPath: audioURL.path)[.size]) as? NSNumber)?.int64Value ?? -1
        onboardingLogger.info("Starting onboarding transcription entryID=\(entry.id?.uuidString ?? "missing", privacy: .public) fileExists=\(fileExists, privacy: .public) bytes=\(byteCount, privacy: .public) transcriptionStatus=processing")
        Task {
            let result: Result<FileTranscriptionResult, Error>
            do {
                result = .success(try await TranscriptionService.shared.transcribe(from: audioURL))
            } catch {
                result = .failure(error)
            }
            await MainActor.run {
                guard let entry = try? viewContext.existingObject(with: entryObjectID) as? DiaryEntry,
                      let attachment = try? viewContext.existingObject(with: attachmentObjectID) else {
                    isTranscribing = false
                    return
                }
                switch result {
                case .success(let transcription):
                    let text = transcription.text
                    response.speechChoice = .granted
                    firstEntryDraft = text
                    response.firstEntryText = text
                    guard let transcriptBlock = JournalBlockTimelineStore.upsertTranscriptBlock(
                        text: text,
                        createdAt: entry.date ?? Date(),
                        attachment: attachment,
                        to: entry,
                        in: viewContext
                    ) else {
                        isTranscribing = false
                        return
                    }
                    JournalBlockTimelineStore.appendMoodBlock(mood: selectedMood, createdAt: entry.date ?? Date(), to: entry, in: viewContext)
                    AudioAttachmentStore.markTranscriptionCompleted(
                        attachment,
                        engine: transcription.engine.rawValue,
                        locale: transcription.locale,
                        transcriptBlockID: transcriptBlock.blockID
                    )
                    try? viewContext.save()
                    onboardingLogger.info("Onboarding transcript saved entryID=\(entry.id?.uuidString ?? "missing", privacy: .public) chars=\(text.count, privacy: .public) transcriptionStatus=completed")
                    EntryLearningPipeline.processSavedEntry(
                        text: text,
                        mood: selectedMood.rawValue,
                        date: entry.date ?? Date(),
                        duration: entry.duration
                    )
                    EntryLearningPipeline.upsertSemanticEntry(entry)
                    HapticManager.shared.entrySaved()
                    entryCreated = true
                case .failure(let error):
                    response.speechChoice = .denied
                    AudioAttachmentStore.markTranscriptionFailed(attachment, error: error)
                    try? viewContext.save()
                    let nsError = error as NSError
                    onboardingLogger.error("Onboarding transcription failed entryID=\(entry.id?.uuidString ?? "missing", privacy: .public) domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public) transcriptionStatus=failed")
                    onboardingError = String(localized: "Recording saved. Add a few words before continuing.")
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
            JournalBlockTimelineStore.appendTextBlock(text: text, createdAt: existingEntry.date ?? Date(), to: existingEntry, in: viewContext)
            existingEntry.updatedAt = Date()
            JournalBlockTimelineStore.appendMoodBlock(mood: selectedMood, createdAt: existingEntry.date ?? Date(), to: existingEntry, in: viewContext)
            try? viewContext.save()
            entry = existingEntry
        } else {
            entry = createEntry(text: text, audioURL: nil, duration: 0)
        }
        entryCreated = true
        response.firstEntryText = text
        EntryLearningPipeline.processSavedEntry(
            text: text,
            mood: selectedMood.rawValue,
            date: entry.date ?? Date(),
            duration: entry.duration
        )
        EntryLearningPipeline.upsertSemanticEntry(entry)
        HapticManager.shared.entrySaved()
        goForward()
    }

    @discardableResult
    private func createEntry(text: String, audioURL: URL?, duration: TimeInterval) -> DiaryEntry {
        let now = Date()
        let entry: DiaryEntry
        let createdFallbackEntry: Bool
        do {
            entry = try DiaryEntryDailyStore.getOrCreateEntry(on: now, in: viewContext)
            createdFallbackEntry = false
        } catch {
            entry = DiaryEntry(context: viewContext)
            entry.id = UUID()
            entry.date = now
            entry.createdAt = now
            entry.text = ""
            createdFallbackEntry = true
        }
        JournalBlockTimelineStore.appendTextBlock(text: text, createdAt: now, to: entry, in: viewContext)
        entry.updatedAt = now
        if createdFallbackEntry {
            entry.isStarred = false
        }
        if let audioURL {
            let byteCount = ((try? FileManager.default.attributesOfItem(atPath: audioURL.path)[.size]) as? NSNumber)?.int64Value ?? -1
            let attachment = AudioAttachmentStore.attachAudio(
                fileName: audioURL.lastPathComponent,
                duration: duration,
                createdAt: now,
                sourceCaptureID: nil,
                byteCount: byteCount,
                codec: "aac-lc",
                to: entry,
                in: viewContext
            )
            JournalBlockTimelineStore.appendAudioBlock(
                attachment: attachment,
                createdAt: now,
                sourceCaptureID: nil,
                to: entry,
                in: viewContext
            )
        }
        entry.entryTranscriptionStatus = .none
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            JournalBlockTimelineStore.appendMoodBlock(mood: selectedMood, createdAt: now, to: entry, in: viewContext)
        }
        try? viewContext.save()
        return entry
    }

    private func completeOnboarding() {
        authorName = Personalization.trimmedName(from: nameDraft)
        response.completedAt = Date()
        store.save(response)
        withOffRecordAnimation(OffRecordMotion.gentle) {
            hasCompletedOnboarding = true
        }
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
    }

    private func configureForUITestingIfNeeded() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-UITesting") else { return }
        if arguments.contains("-OnboardingFirstEntryTextUITest") {
            response.microphoneChoice = .denied
            firstEntryMode = .textFallback
            step = .firstReflection
        } else if arguments.contains("-OnboardingFirstEntryVoiceUITest") {
            response.microphoneChoice = .notAsked
            firstEntryMode = .voice
            step = .firstReflection
        }
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
