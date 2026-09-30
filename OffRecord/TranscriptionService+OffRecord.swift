//
//  TranscriptionService+OffRecord.swift
//  OffRecord
//
//  App-side wiring for the shared TranscriptionKit service: OffRecord's
//  consent state is injected, keeping the package storage- and app-agnostic.
//

import Foundation
import TranscriptionKit

extension TranscriptionService {
    static let shared = TranscriptionService(
        consentProvider: { SpeechTranscriptionConsent.hasGrantedAppleSpeechProcessing }
    )

    /// Downloads the on-device speech model when consent has been granted.
    /// Preserves the historical call sites' consent-gated behavior.
    static func prewarmPreferredModelIfNeeded() {
        guard SpeechTranscriptionConsent.hasGrantedAppleSpeechProcessing else { return }
        prewarmPreferredModel()
    }
}
