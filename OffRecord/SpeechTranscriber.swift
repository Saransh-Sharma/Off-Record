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

/// Transcribes audio recordings to text using Apple's Speech framework.
/// Requires explicit consent because online recognition may be processed by Apple Speech.
final class SpeechTranscriber {
    
    // MARK: - Shared Instance
    
    static let shared = SpeechTranscriber()

    // MARK: - Private Properties
    
    private let networkMonitor = NWPathMonitor()
    private var isOnline = true
    
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
                return "Your recording is saved. Allow Apple Speech transcription before OffRecord turns voice into text."
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
                completion(.failure(TranscriptionError.appleSpeechConsentRequired))
            }
            return
        }

        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                guard status == .authorized else {
                    completion(.failure(TranscriptionError.notAuthorized))
                    return
                }

                guard let recognizer = SFSpeechRecognizer() else {
                    completion(.failure(TranscriptionError.recognizerUnavailable))
                    return
                }

                guard recognizer.isAvailable else {
                    completion(.failure(TranscriptionError.recognizerUnavailable))
                    return
                }

                let request = SFSpeechURLRecognitionRequest(url: audioURL)
                request.shouldReportPartialResults = false

                // When online, Apple Speech may process audio and return a transcript.
                // OffRecord gates this path behind explicit user consent.
                if recognizer.supportsOnDeviceRecognition && !self.isOnline {
                    request.requiresOnDeviceRecognition = true
                } else {
                    request.addsPunctuation = true
                }

                _ = recognizer.recognitionTask(with: request) { result, error in
                    DispatchQueue.main.async {
                        if let error = error {
                            // Check if it's a network error
                            let nsError = error as NSError
                            if nsError.domain == "kAFAssistantErrorDomain" || !self.isOnline {
                                // Offline or network error - inform user
                                completion(.failure(TranscriptionError.offlineNoTranscription))
                            } else {
                                completion(.failure(error))
                            }
                            return
                        }

                        if let result = result, result.isFinal {
                            var text = result.bestTranscription.formattedString

                            // If offline transcription (no punctuation), add basic sentence ending
                            if !text.isEmpty && !text.hasSuffix(".") && !text.hasSuffix("?") && !text.hasSuffix("!") {
                                text += "."
                            }

                            completion(.success(text))
                        }
                    }
                }
            }
        }
    }
}
#endif
