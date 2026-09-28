//
//  TranscriptionEngine.swift
//  TranscriptionKit
//
//  Engine-neutral types for on-device speech-to-text transcription.
//
//  Privacy: host apps do not send audio or journal data to developer servers
//  or non-Apple AI services.
//

import Foundation

public enum TranscriptionEngineKind: String, Sendable {
    case speechTranscriber
    case dictationTranscriber
}

public struct TranscriptionSegment: Sendable, Equatable {
    public let text: String
    public let startTime: TimeInterval
    public let duration: TimeInterval

    public init(text: String, startTime: TimeInterval, duration: TimeInterval) {
        self.text = text
        self.startTime = startTime
        self.duration = duration
    }
}

public struct FileTranscriptionResult: Sendable {
    public let text: String
    public let engine: TranscriptionEngineKind
    public let locale: Locale
    public let processingDuration: TimeInterval
    public let segments: [TranscriptionSegment]

    public init(
        text: String,
        engine: TranscriptionEngineKind,
        locale: Locale,
        processingDuration: TimeInterval,
        segments: [TranscriptionSegment] = []
    ) {
        self.text = text
        self.engine = engine
        self.locale = locale
        self.processingDuration = processingDuration
        self.segments = segments
    }
}

public enum TranscriptionError: LocalizedError, Sendable {
    case recognizerUnavailable
    case noFinalResult
    case appleSpeechConsentRequired
    case modelNotInstalled
    case localeUnsupported
    case unsupportedOS
    case audioConversionFailed

    public var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            return "This device doesn’t support transcription."
        case .noFinalResult:
            return "No speech was recognized."
        case .appleSpeechConsentRequired:
            return "Transcription is turned off."
        case .modelNotInstalled:
            return "The speech model couldn’t be downloaded. Try again later."
        case .localeUnsupported:
            return "Transcription doesn’t support your language yet."
        case .unsupportedOS:
            return "Transcription needs iOS 26 or later."
        case .audioConversionFailed:
            return "This recording couldn’t be transcribed."
        }
    }
}

public protocol TranscriptionEngine: Sendable {
    var kind: TranscriptionEngineKind { get }
    func transcribeFile(at url: URL) async throws -> FileTranscriptionResult
}

public enum TranscriptionPostProcessing {
    /// Matches the historical behavior of ending a transcript with terminal punctuation.
    public static func appendingTerminalPunctuation(to text: String) -> String {
        var text = text
        if !text.isEmpty && !text.hasSuffix(".") && !text.hasSuffix("?") && !text.hasSuffix("!") {
            text += "."
        }
        return text
    }
}
