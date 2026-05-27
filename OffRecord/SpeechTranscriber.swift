//
//  SpeechTranscriber.swift
//  OffRecord
//
//  Handles speech-to-text transcription using Apple's Speech framework.
//  Recognition can use Apple Speech servers when online after explicit consent.
//
//  Privacy: OffRecord does not send audio or journal data to developer servers
//  or non-Apple AI services.
//

#if os(iOS)
import Foundation
import Speech
import Network
import os.log

private let transcriptionLogger = Logger(subsystem: "com.singularity.offrecord", category: "SpeechTranscription")

/// Transcribes audio recordings to text using Apple's Speech framework.
/// Requires explicit consent because online recognition may be processed by Apple Speech.
final class SpeechTranscriber {
    
    // MARK: - Shared Instance
    
    static let shared = SpeechTranscriber()

    // MARK: - Private Properties
    
    private let networkMonitor = NWPathMonitor()
    private var isOnline = true
    private var activeTranscriptionID: UUID?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var timeoutWorkItem: DispatchWorkItem?
    private let transcriptionTimeout: TimeInterval = 180
    
    // MARK: - Error Types

    enum TranscriptionError: LocalizedError {
        case notAuthorized
        case recognizerUnavailable
        case noFinalResult
        case offlineNoTranscription
        case appleSpeechConsentRequired

        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                return "Speech recognition is not authorized."
            case .recognizerUnavailable:
                return "Speech recognizer is not available."
            case .noFinalResult:
                return "No final transcription result."
            case .offlineNoTranscription:
                return "You're offline. Your recording is saved—tap Edit to add text manually, or transcription will happen when you're back online."
            case .appleSpeechConsentRequired:
                return "Speech transcription needs iOS permission. Your recording is saved, and you can type manually."
            }
        }
    }

    init() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            self?.isOnline = path.status == .satisfied
        }
        networkMonitor.start(queue: DispatchQueue.global(qos: .background))
    }

    deinit {
        networkMonitor.cancel()
        timeoutWorkItem?.cancel()
        recognitionTask?.cancel()
    }

    var hasNetworkConnection: Bool {
        isOnline
    }

    // MARK: - Transcription
    
    /// Transcribes audio from the given URL to text.
    /// Uses on-device recognition when offline and may use Apple Speech servers when online for better punctuation.
    /// - Parameters:
    ///   - audioURL: URL to the audio file to transcribe
    ///   - completion: Called with the transcription result or error
    func transcribe(from audioURL: URL, completion: @escaping (Result<String, Error>) -> Void) {
        guard SpeechTranscriptionConsent.hasGrantedAppleSpeechProcessing else {
            DispatchQueue.main.async {
                transcriptionLogger.warning("Transcription blocked because Apple Speech consent is missing")
                completion(.failure(TranscriptionError.appleSpeechConsentRequired))
            }
            return
        }

        let transcriptionID = UUID()
        DispatchQueue.main.async { [weak self] in
            self?.startTranscription(id: transcriptionID, audioURL: audioURL, completion: completion)
        }
    }

    private func startTranscription(
        id transcriptionID: UUID,
        audioURL: URL,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        cancelCurrentTranscription()
        activeTranscriptionID = transcriptionID

        let fileExists = FileManager.default.fileExists(atPath: audioURL.path)
        let byteCount = ((try? FileManager.default.attributesOfItem(atPath: audioURL.path)[.size]) as? NSNumber)?.int64Value ?? -1
        transcriptionLogger.info("Transcription request started id=\(transcriptionID.uuidString, privacy: .public) fileExists=\(fileExists, privacy: .public) bytes=\(byteCount, privacy: .public)")

        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                self?.handleAuthorization(
                    status,
                    transcriptionID: transcriptionID,
                    audioURL: audioURL,
                    completion: completion
                )
            }
        }
    }

    private func handleAuthorization(
        _ status: SFSpeechRecognizerAuthorizationStatus,
        transcriptionID: UUID,
        audioURL: URL,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard activeTranscriptionID == transcriptionID else {
            transcriptionLogger.debug("Ignoring authorization callback for stale transcription id=\(transcriptionID.uuidString, privacy: .public)")
            return
        }

        transcriptionLogger.info("Speech authorization returned id=\(transcriptionID.uuidString, privacy: .public) status=\(String(describing: status), privacy: .public)")
        guard status == .authorized else {
            completeTranscription(
                id: transcriptionID,
                result: .failure(TranscriptionError.notAuthorized),
                completion: completion
            )
            return
        }

        guard let recognizer = SFSpeechRecognizer() else {
            transcriptionLogger.error("Speech recognizer unavailable id=\(transcriptionID.uuidString, privacy: .public) reason=nilRecognizer")
            completeTranscription(
                id: transcriptionID,
                result: .failure(TranscriptionError.recognizerUnavailable),
                completion: completion
            )
            return
        }

        transcriptionLogger.info("Speech recognizer checked id=\(transcriptionID.uuidString, privacy: .public) available=\(recognizer.isAvailable, privacy: .public) supportsOnDevice=\(recognizer.supportsOnDeviceRecognition, privacy: .public)")
        guard recognizer.isAvailable else {
            completeTranscription(
                id: transcriptionID,
                result: .failure(TranscriptionError.recognizerUnavailable),
                completion: completion
            )
            return
        }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false

        let usesOnDeviceRecognition = recognizer.supportsOnDeviceRecognition && !isOnline
        if usesOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        } else {
            request.addsPunctuation = true
        }
        transcriptionLogger.info("Speech request configured id=\(transcriptionID.uuidString, privacy: .public) onDevice=\(usesOnDeviceRecognition, privacy: .public) online=\(self.isOnline, privacy: .public)")

        let timeoutWorkItem = DispatchWorkItem { [weak self] in
            guard let self, self.activeTranscriptionID == transcriptionID else { return }
            transcriptionLogger.error("Speech transcription timed out id=\(transcriptionID.uuidString, privacy: .public) seconds=\(self.transcriptionTimeout, privacy: .public)")
            self.completeTranscription(
                id: transcriptionID,
                result: .failure(TranscriptionError.noFinalResult),
                cancelTask: true,
                completion: completion
            )
        }
        self.timeoutWorkItem = timeoutWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + transcriptionTimeout, execute: timeoutWorkItem)

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                self?.handleRecognitionCallback(
                    result: result,
                    error: error,
                    transcriptionID: transcriptionID,
                    completion: completion
                )
            }
        }
    }

    private func handleRecognitionCallback(
        result: SFSpeechRecognitionResult?,
        error: Error?,
        transcriptionID: UUID,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard activeTranscriptionID == transcriptionID else {
            transcriptionLogger.debug("Ignoring recognition callback for stale transcription id=\(transcriptionID.uuidString, privacy: .public)")
            return
        }

        if let error {
            let nsError = error as NSError
            transcriptionLogger.error("Speech recognition error id=\(transcriptionID.uuidString, privacy: .public) domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public)")
            if nsError.domain == "kAFAssistantErrorDomain" || !isOnline {
                completeTranscription(
                    id: transcriptionID,
                    result: .failure(TranscriptionError.offlineNoTranscription),
                    completion: completion
                )
            } else {
                completeTranscription(id: transcriptionID, result: .failure(error), completion: completion)
            }
            return
        }

        guard let result else {
            transcriptionLogger.debug("Speech recognition callback without result id=\(transcriptionID.uuidString, privacy: .public)")
            return
        }

        let segmentCount = result.bestTranscription.segments.count
        let rawCharacterCount = result.bestTranscription.formattedString.count
        transcriptionLogger.info("Speech recognition callback id=\(transcriptionID.uuidString, privacy: .public) isFinal=\(result.isFinal, privacy: .public) chars=\(rawCharacterCount, privacy: .public) segments=\(segmentCount, privacy: .public)")

        guard result.isFinal else { return }

        var text = result.bestTranscription.formattedString
        if !text.isEmpty && !text.hasSuffix(".") && !text.hasSuffix("?") && !text.hasSuffix("!") {
            text += "."
        }

        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            completeTranscription(
                id: transcriptionID,
                result: .failure(TranscriptionError.noFinalResult),
                completion: completion
            )
        } else {
            completeTranscription(id: transcriptionID, result: .success(text), completion: completion)
        }
    }

    @discardableResult
    private func completeTranscription(
        id transcriptionID: UUID,
        result: Result<String, Error>,
        cancelTask: Bool = false,
        completion: @escaping (Result<String, Error>) -> Void
    ) -> Bool {
        guard activeTranscriptionID == transcriptionID else {
            transcriptionLogger.debug("Ignoring completion for stale transcription id=\(transcriptionID.uuidString, privacy: .public)")
            return false
        }

        activeTranscriptionID = nil
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        if cancelTask {
            recognitionTask?.cancel()
        }
        recognitionTask = nil

        switch result {
        case .success(let text):
            transcriptionLogger.info("Speech transcription completed id=\(transcriptionID.uuidString, privacy: .public) chars=\(text.count, privacy: .public)")
        case .failure(let error):
            let nsError = error as NSError
            transcriptionLogger.error("Speech transcription completed with failure id=\(transcriptionID.uuidString, privacy: .public) domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public)")
        }

        completion(result)
        return true
    }

    private func cancelCurrentTranscription() {
        if let activeTranscriptionID {
            transcriptionLogger.info("Cancelling existing transcription id=\(activeTranscriptionID.uuidString, privacy: .public)")
        }
        activeTranscriptionID = nil
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        recognitionTask?.cancel()
        recognitionTask = nil
    }
}
#endif
