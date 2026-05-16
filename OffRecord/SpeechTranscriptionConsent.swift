//
//  SpeechTranscriptionConsent.swift
//  OffRecord
//
//  Shared disclosure and consent state for Apple Speech transcription.
//

import Foundation

enum SpeechTranscriptionConsent {
    static let appleSpeechProcessingKey = "offrecord.appleSpeechProcessingConsentGranted"

    static var hasGrantedAppleSpeechProcessing: Bool {
        UserDefaults.standard.bool(forKey: appleSpeechProcessingKey)
    }

    static func grantAppleSpeechProcessing() {
        UserDefaults.standard.set(true, forKey: appleSpeechProcessingKey)
    }

    static func revokeAppleSpeechProcessing() {
        UserDefaults.standard.set(false, forKey: appleSpeechProcessingKey)
    }

    static let disclosureTitle = "Allow Apple Speech Transcription?"

    static let disclosureMessage = """
    OffRecord uses Apple Speech to turn your voice into text. When your device is online, your voice audio may be sent to Apple for speech recognition, and Apple returns the transcript. The transcript is saved in your journal.

    OffRecord does not send your journal or audio to developer servers or non-Apple AI services.
    """

    static let settingsDescription = "When enabled, voice audio may be processed by Apple Speech when your device is online. OffRecord stores the returned transcript in your journal and does not send your data to developer servers or non-Apple AI services."
}

enum OffRecordExternalLinks {
    static let privacyPolicyURL = URL(string: "https://saransh-sharma.github.io/Off-Record/privacy.html")
    static let supportURL = URL(string: "https://saransh-sharma.github.io/Off-Record/support.html")
    static let marketingURL = URL(string: "https://saransh-sharma.github.io/Off-Record/")
}
