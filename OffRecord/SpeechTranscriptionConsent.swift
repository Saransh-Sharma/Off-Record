//
//  SpeechTranscriptionConsent.swift
//  OffRecord
//
//  Shared disclosure and consent state for on-device SpeechAnalyzer transcription.
//

import Foundation
import TranscriptionKit

enum SpeechTranscriptionConsent {
    static let appleSpeechProcessingKey = "offrecord.appleSpeechProcessingConsentGranted"

    static var hasGrantedAppleSpeechProcessing: Bool {
        UserDefaults.standard.bool(forKey: appleSpeechProcessingKey)
    }

    static func grantAppleSpeechProcessing() {
        UserDefaults.standard.set(true, forKey: appleSpeechProcessingKey)
        #if os(iOS)
        TranscriptionService.prewarmPreferredModelIfNeeded()
        #endif
    }

    static func revokeAppleSpeechProcessing() {
        UserDefaults.standard.set(false, forKey: appleSpeechProcessingKey)
        #if os(iOS)
        if #available(iOS 26.0, *) {
            Task {
                await TranscriptionAssetManager.shared.releaseReservedModels()
            }
        }
        #endif
    }

    static let disclosureTitle = "On-Device Transcription"

    static var disclosureMessage: String {
        return """
        OffRecord uses Apple’s SpeechAnalyzer to turn your voice into text entirely on your device. Apple may download a language model to your device when needed. If your language is not supported, your recording stays saved and OffRecord will not send it to a server for transcription.

        The transcript is saved in your journal. OffRecord does not send your journal or audio to developer servers, speech-recognition servers, or non-Apple AI services.
        """
    }

    static var settingsDescription: String {
        "Voice transcription runs entirely on your device with Apple SpeechAnalyzer. Apple may download a language model when needed; unsupported languages never fall back to server transcription."
    }
}

enum OffRecordExternalLinks {
    static let privacyPolicyURL = URL(string: "https://saransh-sharma.github.io/Off-Record/privacy.html")
    static let supportURL = URL(string: "https://saransh-sharma.github.io/Off-Record/support.html")
    static let marketingURL = URL(string: "https://saransh-sharma.github.io/Off-Record/")
}
