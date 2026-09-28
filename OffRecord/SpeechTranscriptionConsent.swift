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

    static let disclosureTitle = "Transcribe Recordings?"

    static var disclosureMessage: String {
        "OffRecord uses Apple’s on-device speech recognition. Your audio is never sent to a server. iOS may download a language file first."
    }

    static var settingsDescription: String {
        "Uses Apple’s on-device speech recognition. Unsupported languages keep the recording without a transcript."
    }
}

enum OffRecordExternalLinks {
    static let privacyPolicyURL = URL(string: "https://saransh-sharma.github.io/Off-Record/privacy.html")
    static let supportURL = URL(string: "https://saransh-sharma.github.io/Off-Record/support.html")
    static let marketingURL = URL(string: "https://saransh-sharma.github.io/Off-Record/")
}
