//
//  VoiceSearchManager.swift
//  OffRecord
//
//  Live search dictation through TranscriptionKit's SpeechAnalyzer session.
//

#if os(iOS)
import AVFoundation
import Foundation
import TranscriptionKit

@MainActor
final class VoiceSearchManager: ObservableObject {
    @Published var transcribedText = ""
    @Published var isListening = false
    @Published var isPreparingModel = false
    @Published var modelDownloadProgress: Double?
    @Published var errorMessage: String?

    private var session: LiveTranscriptionSession?
    private var preparationTask: Task<Void, Never>?
    private var eventsTask: Task<Void, Never>?
    private var autoStopTask: Task<Void, Never>?

    deinit {
        preparationTask?.cancel()
        eventsTask?.cancel()
        autoStopTask?.cancel()
        if let session {
            Task { await session.cancel() }
        }
    }

    func startListening() {
        guard SpeechTranscriptionConsent.hasGrantedAppleSpeechProcessing else {
            errorMessage = VoiceSearchError.transcriptionConsentRequired.errorDescription
            return
        }

        stopListening()
        transcribedText = ""
        errorMessage = nil
        isPreparingModel = true
        modelDownloadProgress = nil

        preparationTask = Task { [weak self] in
            guard let self else { return }
            do {
                guard await AVAudioApplication.requestRecordPermission() else {
                    throw VoiceSearchError.microphonePermissionDenied
                }
                try self.configureAudioSession()

                let prepared = try await LiveTranscriptionSession.prepare(
                    preferredLocale: .current,
                    modelProgress: { progress in
                        Task { @MainActor [weak self] in
                            self?.modelDownloadProgress = progress
                        }
                    }
                )
                try Task.checkCancellation()
                self.session = prepared
                self.consumeEvents(from: prepared)
                try await prepared.start()
                self.isPreparingModel = false
                self.modelDownloadProgress = nil
                self.isListening = true
                self.scheduleAutoStop()
            } catch is CancellationError {
                self.isPreparingModel = false
            } catch {
                self.isPreparingModel = false
                self.modelDownloadProgress = nil
                self.isListening = false
                self.errorMessage = error.localizedDescription
                if let session = self.session {
                    self.session = nil
                    await session.cancel()
                }
            }
        }
    }

    func stopListening() {
        preparationTask?.cancel()
        preparationTask = nil
        autoStopTask?.cancel()
        autoStopTask = nil
        isPreparingModel = false
        modelDownloadProgress = nil

        guard let activeSession = session else {
            isListening = false
            return
        }
        session = nil
        Task { [weak self] in
            do {
                try await activeSession.stop()
            } catch {
                self?.errorMessage = error.localizedDescription
            }
            self?.isListening = false
            self?.eventsTask = nil
        }
    }

    private func consumeEvents(from session: LiveTranscriptionSession) {
        eventsTask?.cancel()
        eventsTask = Task { [weak self] in
            for await event in session.events {
                guard !Task.isCancelled else { return }
                switch event {
                case .transcript(let text):
                    self?.transcribedText = text
                case .failure(let message):
                    self?.errorMessage = message
                    self?.stopListening()
                }
            }
        }
    }

    private func configureAudioSession() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func scheduleAutoStop() {
        autoStopTask?.cancel()
        autoStopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, self?.isListening == true else { return }
            self?.stopListening()
            HapticManager.shared.recordingStopped()
        }
    }
}

private enum VoiceSearchError: LocalizedError {
    case microphonePermissionDenied
    case transcriptionConsentRequired

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return String(localized: "Turn on microphone access in Settings to search by voice.")
        case .transcriptionConsentRequired:
            return String(localized: "Turn on transcription in Settings to search by voice.")
        }
    }
}
#endif
