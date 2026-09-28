//
//  CaptureController.swift
//  OffRecord
//
//  App-wide voice capture state. Owns the recorder, live transcription,
//  saving into the day's entry, post-save transcription, the "Saved" moment
//  (quick mood, undo), and capture errors. Any tab can start a capture.
//

import AVFoundation
import CoreData
import PhotosUI
import SwiftUI
import TranscriptionKit
import UIKit
import os.log

private let captureLogger = Logger(subsystem: "com.singularity.offrecord", category: "Capture")

/// Legacy recording state still used by a few surfaces (onboarding, iPad panel copy).
enum RecordingState: Equatable {
    case idle
    case starting
    case recording
    case processing
}

enum CapturePhase: Equatable {
    case idle
    case starting
    case recording
    case paused
    case saved

    var isCapturing: Bool {
        self == .starting || self == .recording || self == .paused
    }
}

enum CaptureTranscriptionState: Equatable {
    case waiting
    case transcribing
    case done(String)
    case needsConsent
    case failed(String)
}

struct SavedCapture: Identifiable, Equatable {
    let id = UUID()
    let entryObjectID: NSManagedObjectID
    let entryID: UUID?
    let attachmentObjectID: NSManagedObjectID
    let audioBlockObjectID: NSManagedObjectID?
    let entryWasEmptyBeforeCapture: Bool
    let duration: TimeInterval
    let capturedAt: Date
    var livePreview: String
    var transcription: CaptureTranscriptionState
    var mood: Mood?
    var moodBlockObjectID: NSManagedObjectID?

    var dayLabel: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(capturedAt) { return "today" }
        if calendar.isDateInYesterday(capturedAt) { return "yesterday" }
        return capturedAt.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}

enum CaptureAlert: Identifiable, Equatable {
    case microphoneDenied
    case recordingFailed
    case saveFailed
    case transcriptionFailed(String)
    case photoImportFailed(failed: Int)
    case entryCreationFailed

    var id: String { title }

    var title: String {
        switch self {
        case .microphoneDenied: return "Microphone Access Needed"
        case .recordingFailed: return "Couldn't Start Recording"
        case .saveFailed: return "Recording Not Saved"
        case .transcriptionFailed: return "Transcription Unavailable"
        case .photoImportFailed: return "Some Photos Weren't Added"
        case .entryCreationFailed: return "Couldn't Open Today's Entry"
        }
    }

    var message: String {
        switch self {
        case .microphoneDenied:
            return "Allow microphone access in Settings to record voice entries. You can still write or add photos."
        case .recordingFailed:
            return "Another app may be using the microphone. Try again in a moment."
        case .saveFailed:
            return "OffRecord couldn't save that recording to your journal. Please try again."
        case .transcriptionFailed(let reason):
            return "\(reason) Your recording is saved — open the entry to listen or add text."
        case .photoImportFailed(let failed):
            return failed == 1
                ? "One photo couldn't be imported. Try choosing it again."
                : "\(failed) photos couldn't be imported. Try choosing them again."
        case .entryCreationFailed:
            return "Please try again."
        }
    }

    var offersSettingsLink: Bool {
        self == .microphoneDenied
    }
}

enum PhotoImportState: Equatable {
    case idle
    case importing(Int)
    case imported(Int)
}

@MainActor
final class CaptureController: ObservableObject {
    static let shared = CaptureController()

    static let liveTranscriptPreferenceKey = "offrecord.capture.showsLiveTranscript"
    static let longRecordingWarningSeconds: TimeInterval = 30 * 60

    @Published private(set) var phase: CapturePhase = .idle {
        didSet { CaptureLiveActivityManager.shared.captureDidChange(from: oldValue, to: phase) }
    }
    @Published var isPanelPresented = false
    @Published var captureDate = Date()
    /// The prompt the person chose to answer, shown in the panel while they speak.
    @Published private(set) var activePrompt: String?
    @Published private(set) var liveTranscript = ""
    @Published private(set) var isLiveTranscriptActive = false
    @Published var showsLiveTranscript: Bool {
        didSet { UserDefaults.standard.set(showsLiveTranscript, forKey: Self.liveTranscriptPreferenceKey) }
    }
    @Published private(set) var savedCapture: SavedCapture?
    @Published var alert: CaptureAlert?
    @Published var isSpeechConsentPromptPresented = false
    @Published private(set) var photoImport: PhotoImportState = .idle
    /// Incremented when a capture is saved; views use it as a sensory feedback / celebration trigger.
    @Published private(set) var savedCount = 0

    let recorder = AudioRecorder()

    private var liveSession: AnyObject?
    private var liveEventsTask: Task<Void, Never>?
    private var autoDismissTask: Task<Void, Never>?
    private var photoImportResetTask: Task<Void, Never>?
    private var pendingConsentCaptureID: UUID?

    private var viewContext: NSManagedObjectContext {
        PersistenceController.shared.container.viewContext
    }

    private init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.liveTranscriptPreferenceKey) == nil {
            defaults.set(true, forKey: Self.liveTranscriptPreferenceKey)
        }
        showsLiveTranscript = defaults.bool(forKey: Self.liveTranscriptPreferenceKey)
        recorder.prepareForFirstUse()
    }

    /// Mirrors the old four-state model for surfaces that only need coarse state.
    var legacyRecordingState: RecordingState {
        switch phase {
        case .idle, .saved: return .idle
        case .starting: return .starting
        case .recording, .paused: return .recording
        }
    }

    var isCaptureDateToday: Bool {
        Calendar.current.isDateInToday(captureDate)
    }

    // MARK: - Recording

    func toggleRecording() {
        switch phase {
        case .idle, .saved:
            startRecording()
        case .recording, .paused:
            finishRecording()
        case .starting:
            break
        }
    }

    func startRecording(prompt: String? = nil) {
        guard phase == .idle || phase == .saved else {
            isPanelPresented = true
            return
        }
        activePrompt = prompt
        PerformanceSignposts.event("RecordTap")
        cancelAutoDismiss()
        savedCapture = nil
        liveTranscript = ""
        phase = .starting
        isPanelPresented = true

        if ProcessInfo.processInfo.arguments.contains("-HeroNudgeUITest") {
            phase = .recording
            HapticManager.shared.recordingStarted()
            return
        }

        // App Store screenshots: a recording in progress, without the microphone.
        if ProcessInfo.processInfo.arguments.contains("-ScreenshotMode") {
            phase = .recording
            recorder.showScreenshotSample(duration: 83)
            liveTranscript = "Quick check-in before work. I slept properly for the first time this week, and the walk this morning really helped. I think I'm finally ready to tell Mike I want to lead the next launch"
            return
        }

        AVAudioApplication.requestRecordPermission { granted in
            Task { @MainActor in
                guard self.phase == .starting else { return }
                guard granted else {
                    self.phase = .idle
                    self.isPanelPresented = false
                    self.alert = .microphoneDenied
                    HapticManager.shared.warning()
                    return
                }
                do {
                    try self.recorder.startRecording()
                    self.phase = .recording
                    HapticManager.shared.recordingStarted()
                    self.startLiveTranscriptionIfPossible()
                } catch {
                    captureLogger.error("Recorder failed to start: \(error.localizedDescription, privacy: .public)")
                    self.phase = .idle
                    self.isPanelPresented = false
                    self.alert = .recordingFailed
                    HapticManager.shared.error()
                }
            }
        }
    }

    func togglePause() {
        switch phase {
        case .recording:
            recorder.pause()
            phase = .paused
            HapticManager.shared.selectionChanged()
        case .paused:
            do {
                try recorder.resume()
                phase = .recording
                HapticManager.shared.selectionChanged()
            } catch {
                alert = .recordingFailed
            }
        default:
            break
        }
    }

    /// Keeps `phase` aligned when the system pauses the recorder (e.g. a call).
    func syncWithRecorderInterruption() {
        if recorder.wasInterrupted && phase == .recording {
            phase = .paused
        }
    }

    func discardRecording() {
        guard phase.isCapturing else { return }
        activePrompt = nil
        stopLiveTranscription()
        recorder.discardRecording()
        phase = .idle
        isPanelPresented = false
        HapticManager.shared.entryDeleted()
    }

    func finishRecording() {
        guard phase == .recording || phase == .paused else { return }
        HapticManager.shared.recordingStopped()
        let preview = liveTranscript
        activePrompt = nil
        stopLiveTranscription()

        if ProcessInfo.processInfo.arguments.contains("-CaptureSpeechConsentUITest"),
           let testAudioURL = makeUITestRecordingFile() {
            _ = recorder.stopRecording()
            save(audioURL: testAudioURL, duration: 4, livePreview: preview)
            return
        }

        guard let result = recorder.stopRecording() else {
            phase = .idle
            isPanelPresented = false
            return
        }

        // Treat an accidental tap-tap as no recording at all.
        if result.duration < 0.6 && !ProcessInfo.processInfo.arguments.contains("-HeroNudgeUITest") {
            try? FileManager.default.removeItem(at: result.url)
            phase = .idle
            isPanelPresented = false
            return
        }
        save(audioURL: result.url, duration: result.duration, livePreview: preview)
    }

    // MARK: - Live transcription

    private func startLiveTranscriptionIfPossible() {
        guard showsLiveTranscript,
              SpeechTranscriptionConsent.hasGrantedAppleSpeechProcessing,
              recorder.supportsBufferStreaming else { return }

        liveEventsTask = Task { [weak self] in
            do {
                let session = try await LiveTranscriptionSession.prepare()
                try await session.startWithExternalInput()
                guard let self, !Task.isCancelled, self.phase.isCapturing else {
                    await session.cancel()
                    return
                }
                self.liveSession = session
                self.isLiveTranscriptActive = true
                self.recorder.bufferHandler = { buffer in
                    session.appendExternal(buffer)
                }
                for await event in session.events {
                    if Task.isCancelled { break }
                    if case .transcript(let text) = event {
                        self.liveTranscript = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            } catch {
                captureLogger.info("Live transcript unavailable: \(error.localizedDescription, privacy: .public)")
                self?.isLiveTranscriptActive = false
            }
        }
    }

    private func stopLiveTranscription() {
        recorder.bufferHandler = nil
        liveEventsTask?.cancel()
        liveEventsTask = nil
        isLiveTranscriptActive = false
        if let session = liveSession as? LiveTranscriptionSession {
            Task { await session.cancel() }
        }
        liveSession = nil
    }

    // MARK: - Saving

    private func save(audioURL: URL, duration: TimeInterval, livePreview: String) {
        let now = captureTimestamp()
        let context = viewContext
        let entry: DiaryEntry
        do {
            entry = try DiaryEntryDailyStore.getOrCreateEntry(on: now, in: context)
        } catch {
            entry = DiaryEntry(context: context)
            entry.id = UUID()
            entry.date = now
            entry.createdAt = now
            entry.text = ""
            entry.isStarred = false
        }
        let entryWasEmpty = !entry.isStartedEntry

        let byteCount = ((try? FileManager.default.attributesOfItem(atPath: audioURL.path)[.size]) as? NSNumber)?.int64Value ?? -1
        let attachment = AudioAttachmentStore.attachAudio(
            fileName: audioURL.lastPathComponent,
            duration: duration,
            createdAt: now,
            sourceCaptureID: nil,
            byteCount: byteCount,
            codec: "aac-lc",
            to: entry,
            in: context
        )
        let audioBlock = JournalBlockTimelineStore.appendAudioBlock(
            attachment: attachment,
            createdAt: now,
            sourceCaptureID: nil,
            to: entry,
            in: context
        )
        entry.entryTranscriptionStatus = .processing

        do {
            try context.save()
            JournalSpotlightIndexer.shared.upsert(entry: entry)
        } catch {
            captureLogger.error("Failed to save capture: \(error.localizedDescription, privacy: .public)")
            context.rollback()
            try? FileManager.default.removeItem(at: audioURL)
            phase = .idle
            isPanelPresented = false
            alert = .saveFailed
            HapticManager.shared.error()
            return
        }

        let saved = SavedCapture(
            entryObjectID: entry.objectID,
            entryID: entry.id,
            attachmentObjectID: attachment.objectID,
            audioBlockObjectID: audioBlock?.objectID,
            entryWasEmptyBeforeCapture: entryWasEmpty,
            duration: duration,
            capturedAt: now,
            livePreview: livePreview,
            transcription: .waiting,
            mood: nil,
            moodBlockObjectID: nil
        )
        savedCapture = saved
        withOffRecordAnimation(OffRecordMotion.hero) {
            phase = .saved
        }
        savedCount += 1
        HapticManager.shared.entrySaved()
        ReviewManager.shared.recordEntry()
        scheduleAutoDismiss()

        beginTranscription(for: saved, audioURL: audioURL)
    }

    private func beginTranscription(for saved: SavedCapture, audioURL: URL) {
        guard SpeechTranscriptionConsent.hasGrantedAppleSpeechProcessing else {
            if let attachment = try? viewContext.existingObject(with: saved.attachmentObjectID),
               let entry = try? viewContext.existingObject(with: saved.entryObjectID) as? DiaryEntry {
                attachment.setValue(AudioTranscriptionStatus.none.rawValue, forKey: "transcriptionStatus")
                entry.entryTranscriptionStatus = .none
                try? viewContext.save()
            }
            updateSaved(saved.id) { $0.transcription = .needsConsent }
            pendingConsentCaptureID = saved.id
            cancelAutoDismiss()
            isSpeechConsentPromptPresented = true
            return
        }
        transcribe(saved: saved, audioURL: audioURL)
    }

    func grantSpeechConsentAndTranscribe() {
        SpeechTranscriptionConsent.grantAppleSpeechProcessing()
        scheduleAutoDismiss()
        guard let saved = savedCapture, saved.id == pendingConsentCaptureID,
              let attachment = try? viewContext.existingObject(with: saved.attachmentObjectID),
              let url = AudioAttachmentStore.audioURL(for: attachment) else { return }
        pendingConsentCaptureID = nil
        transcribe(saved: saved, audioURL: url)
    }

    func declineSpeechConsent() {
        pendingConsentCaptureID = nil
        scheduleAutoDismiss()
    }

    private func transcribe(saved: SavedCapture, audioURL: URL) {
        let context = viewContext
        guard let attachment = try? context.existingObject(with: saved.attachmentObjectID) else { return }
        AudioAttachmentStore.markTranscriptionProcessing(attachment)
        try? context.save()
        updateSaved(saved.id) { $0.transcription = .transcribing }

        let entryObjectID = saved.entryObjectID
        let attachmentObjectID = saved.attachmentObjectID
        let capturedAt = saved.capturedAt
        let captureID = saved.id

        Task {
            let result: Result<FileTranscriptionResult, Error>
            do {
                result = .success(try await TranscriptionService.shared.transcribe(from: audioURL))
            } catch {
                result = .failure(error)
            }
            guard let entry = try? context.existingObject(with: entryObjectID) as? DiaryEntry,
                  !entry.isDeleted,
                  let attachment = try? context.existingObject(with: attachmentObjectID),
                  !attachment.isDeleted else {
                captureLogger.info("Skipped transcription result because the capture was removed.")
                return
            }
            PerformanceSignposts.event("TranscriptionCompleted")
            switch result {
            case .success(let transcription):
                let text = transcription.text
                guard let block = JournalBlockTimelineStore.upsertTranscriptBlock(
                    text: text,
                    createdAt: capturedAt,
                    attachment: attachment,
                    to: entry,
                    in: context
                ) else {
                    self.updateSaved(captureID) { $0.transcription = .done("") }
                    return
                }
                AudioAttachmentStore.markTranscriptionCompleted(
                    attachment,
                    engine: transcription.engine.rawValue,
                    locale: transcription.locale,
                    transcriptBlockID: block.blockID
                )
                do {
                    try context.save()
                    self.updateSaved(captureID) { $0.transcription = .done(text) }
                    EntryLearningPipeline.processSavedEntry(
                        text: text,
                        mood: entry.mood,
                        date: entry.date ?? Date(),
                        duration: entry.duration
                    )
                    EntryLearningPipeline.upsertSemanticEntry(entry)
                    JournalSpotlightIndexer.shared.upsert(entry: entry)
                } catch {
                    captureLogger.error("Failed to store transcript: \(error.localizedDescription, privacy: .public)")
                    self.updateSaved(captureID) { $0.transcription = .failed("The transcript couldn't be saved.") }
                }
            case .failure(let error):
                AudioAttachmentStore.markTranscriptionFailed(attachment, error: error)
                try? context.save()
                let reason = (error as? TranscriptionError)?.errorDescription ?? "Transcription didn't finish."
                self.updateSaved(captureID) { $0.transcription = .failed(reason) }
                // Only interrupt with an alert when the saved card is no longer visible.
                if self.savedCapture?.id != captureID || !self.isPanelPresented {
                    self.alert = .transcriptionFailed(reason)
                }
            }
        }
    }

    // MARK: - Saved moment

    func setMood(_ mood: Mood) {
        guard var saved = savedCapture,
              let entry = try? viewContext.existingObject(with: saved.entryObjectID) as? DiaryEntry else { return }
        cancelAutoDismiss()

        if let blockID = saved.moodBlockObjectID,
           let block = try? viewContext.existingObject(with: blockID) as? JournalBlock {
            block.moodValue = mood.rawValue
            block.blockUpdatedAt = Date()
            JournalBlockTimelineStore.recomposeLegacyFields(for: entry, touchUpdatedAt: true)
        } else {
            let block = JournalBlockTimelineStore.appendMoodBlock(
                mood: mood,
                createdAt: saved.capturedAt.addingTimeInterval(0.001),
                to: entry,
                in: viewContext
            )
            saved.moodBlockObjectID = block?.objectID
        }
        do {
            try viewContext.save()
            saved.mood = mood
            savedCapture = saved
            HapticManager.shared.moodSelected()
            HealthStateOfMindWriter.shared.recordMomentaryMood(mood, at: saved.capturedAt)
            JournalSpotlightIndexer.shared.upsert(entry: entry)
        } catch {
            viewContext.rollback()
        }
        scheduleAutoDismiss(after: 4)
    }

    /// Removes the just-saved recording (and its transcript and mood) from the journal.
    func undoLastCapture() {
        guard let saved = savedCapture else { return }
        let context = viewContext
        var fileURLs: [URL] = []

        if let attachment = try? context.existingObject(with: saved.attachmentObjectID),
           let transcriptID = AudioAttachmentStore.transcriptBlockID(of: attachment),
           let entry = try? context.existingObject(with: saved.entryObjectID) as? DiaryEntry,
           let transcriptBlock = JournalBlockTimelineStore.blocks(for: entry).first(where: { $0.blockID == transcriptID }) {
            _ = JournalBlockTimelineStore.deleteBlock(transcriptBlock, in: context)
        }
        if let moodID = saved.moodBlockObjectID,
           let moodBlock = try? context.existingObject(with: moodID) as? JournalBlock {
            _ = JournalBlockTimelineStore.deleteBlock(moodBlock, in: context)
        }
        if let blockID = saved.audioBlockObjectID,
           let block = try? context.existingObject(with: blockID) as? JournalBlock {
            fileURLs += JournalBlockTimelineStore.deleteBlock(block, in: context).fileURLsToRemoveAfterSave
        } else if let attachment = try? context.existingObject(with: saved.attachmentObjectID) {
            if let url = AudioAttachmentStore.audioURL(for: attachment) { fileURLs.append(url) }
            context.delete(attachment)
        }

        var deletedEntryID: UUID?
        if let entry = try? context.existingObject(with: saved.entryObjectID) as? DiaryEntry {
            if saved.entryWasEmptyBeforeCapture && !entry.isStartedEntry {
                deletedEntryID = entry.id
                context.delete(entry)
            } else {
                entry.entryTranscriptionStatus = .none
            }
        }

        do {
            try context.save()
            fileURLs.forEach { try? FileManager.default.removeItem(at: $0) }
            if let deletedEntryID {
                SemanticMemoryIndexController.shared.deleteEntry(id: deletedEntryID)
                JournalSpotlightIndexer.shared.delete(entryID: deletedEntryID)
            } else if let entry = try? context.existingObject(with: saved.entryObjectID) as? DiaryEntry {
                EntryLearningPipeline.upsertSemanticEntry(entry)
                JournalSpotlightIndexer.shared.upsert(entry: entry)
            }
            HapticManager.shared.entryDeleted()
        } catch {
            captureLogger.error("Undo failed: \(error.localizedDescription, privacy: .public)")
            context.rollback()
        }

        savedCapture = nil
        phase = .idle
        isPanelPresented = false
    }

    func dismissSaved() {
        cancelAutoDismiss()
        isPanelPresented = false
        if phase == .saved {
            phase = .idle
        }
    }

    /// Called when the panel is dismissed by gesture. Capture keeps running in the accessory.
    func panelDidDismiss() {
        cancelAutoDismiss()
        if phase == .saved {
            phase = .idle
        }
    }

    func holdSavedCard() {
        cancelAutoDismiss()
    }

    private func scheduleAutoDismiss(after seconds: Double = 7) {
        cancelAutoDismiss()
        guard !UIAccessibility.isVoiceOverRunning, !isSpeechConsentPromptPresented, alert == nil else { return }
        autoDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self, self.phase == .saved else { return }
            self.dismissSaved()
        }
    }

    private func cancelAutoDismiss() {
        autoDismissTask?.cancel()
        autoDismissTask = nil
    }

    private func updateSaved(_ id: UUID, _ update: (inout SavedCapture) -> Void) {
        guard var saved = savedCapture, saved.id == id else { return }
        update(&saved)
        savedCapture = saved
    }

    // MARK: - Photos

    func importPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        let capturedAt = captureTimestamp()
        guard let entry = getOrCreateEntry(capturedAt: capturedAt) else {
            alert = .entryCreationFailed
            return
        }
        let entryObjectID = entry.objectID
        let context = viewContext
        photoImportResetTask?.cancel()
        photoImport = .importing(items.count)

        Task {
            var imported = 0
            var failed = 0
            for item in items {
                let token = PerformanceSignposts.begin("PhotoImport")
                defer { PerformanceSignposts.end(token) }
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let jpegData = await PhotoAttachmentProcessor.shared.preparedJPEGData(from: data),
                      let entry = try? context.existingObject(with: entryObjectID) as? DiaryEntry,
                      let attachment = PhotoStorageManager.shared.addPhotoData(jpegData, to: entry, in: context) else {
                    failed += 1
                    continue
                }
                JournalBlockTimelineStore.appendPhotoBlock(
                    attachment: attachment,
                    createdAt: capturedAt,
                    to: entry,
                    in: context
                )
                entry.updatedAt = Date()
                imported += 1
            }

            if imported > 0, let entry = try? context.existingObject(with: entryObjectID) as? DiaryEntry {
                do {
                    try context.save()
                    JournalSpotlightIndexer.shared.upsert(entry: entry)
                    HapticManager.shared.entrySaved()
                } catch {
                    context.rollback()
                    failed += imported
                    imported = 0
                }
            }

            self.photoImport = imported > 0 ? .imported(imported) : .idle
            if failed > 0 {
                self.alert = .photoImportFailed(failed: failed)
            }
            self.photoImportResetTask = Task {
                try? await Task.sleep(for: .seconds(2.5))
                guard !Task.isCancelled else { return }
                withOffRecordAnimation(OffRecordMotion.fade) {
                    self.photoImport = .idle
                }
            }
        }
    }

    // MARK: - Entries

    func getOrCreateEntry(capturedAt: Date? = nil) -> DiaryEntry? {
        let now = capturedAt ?? captureTimestamp()
        do {
            let entry = try DiaryEntryDailyStore.getOrCreateEntry(on: now, in: viewContext)
            try viewContext.save()
            return entry
        } catch {
            viewContext.rollback()
            return (try? DiaryEntryDailyStore.entries(on: now, in: viewContext).first)
        }
    }

    /// The chosen journal day combined with the current clock time.
    func captureTimestamp(clock: Date = Date()) -> Date {
        let calendar = Calendar.current
        let day = calendar.dateComponents([.year, .month, .day], from: captureDate)
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

    func resetCaptureDateIfStale() {
        guard !phase.isCapturing else { return }
        if !Calendar.current.isDateInToday(captureDate) && captureDate > Date() {
            captureDate = Date()
        }
    }

    private func makeUITestRecordingFile() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let directory = base.appendingPathComponent("Recordings", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("ui-test-recording-\(UUID().uuidString).m4a")
            try Data([0, 1, 2, 3]).write(to: url)
            return url
        } catch {
            return nil
        }
    }

    static func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
