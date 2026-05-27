import Foundation

enum WatchCaptureKind: String, Codable, CaseIterable, Sendable {
    case mood
    case speak
    case audio
}

enum WatchSyncState: String, Codable, Sendable {
    case saved
    case queued
    case sending
    case synced
    case failed
}

enum WatchTransferKind: String, Codable, Sendable {
    case metadata
    case audioFile
}

enum WatchCaptureSourceSurface: String, Codable, Sendable {
    case app
    case complication
    case smartStack
}

enum WatchSpeechTruthState: String, Codable, Sendable {
    case transcriptOnWatchNow = "Transcript on watch now"
    case transcriptOnIPhoneLater = "Transcript on iPhone later"
    case audioOnly = "Audio only"
}

struct WatchRecentCapture: Codable, Identifiable, Hashable, Sendable {
    var id: UUID { envelope.captureID }
    var envelope: WatchCaptureEnvelope
    var syncState: WatchSyncState
    var transferKind: WatchTransferKind
    var attemptCount: Int
    var lastAttemptAtUTC: Date?
    var nextAttemptAtUTC: Date?
    var lastError: String?
    var audioFileMissing: Bool
    var updatedAtUTC: Date

    init(
        envelope: WatchCaptureEnvelope,
        syncState: WatchSyncState,
        transferKind: WatchTransferKind,
        attemptCount: Int = 0,
        lastAttemptAtUTC: Date? = nil,
        nextAttemptAtUTC: Date? = nil,
        lastError: String? = nil,
        audioFileMissing: Bool = false,
        updatedAtUTC: Date
    ) {
        self.envelope = envelope
        self.syncState = syncState
        self.transferKind = transferKind
        self.attemptCount = attemptCount
        self.lastAttemptAtUTC = lastAttemptAtUTC
        self.nextAttemptAtUTC = nextAttemptAtUTC
        self.lastError = lastError
        self.audioFileMissing = audioFileMissing
        self.updatedAtUTC = updatedAtUTC
    }

    private enum CodingKeys: String, CodingKey {
        case envelope
        case syncState
        case transferKind
        case attemptCount
        case lastAttemptAtUTC
        case nextAttemptAtUTC
        case lastError
        case audioFileMissing
        case updatedAtUTC
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        envelope = try container.decode(WatchCaptureEnvelope.self, forKey: .envelope)
        syncState = try container.decode(WatchSyncState.self, forKey: .syncState)
        transferKind = try container.decodeIfPresent(WatchTransferKind.self, forKey: .transferKind)
            ?? (envelope.kind == .audio ? .audioFile : .metadata)
        attemptCount = try container.decodeIfPresent(Int.self, forKey: .attemptCount) ?? 0
        lastAttemptAtUTC = try container.decodeIfPresent(Date.self, forKey: .lastAttemptAtUTC)
        nextAttemptAtUTC = try container.decodeIfPresent(Date.self, forKey: .nextAttemptAtUTC)
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
        audioFileMissing = try container.decodeIfPresent(Bool.self, forKey: .audioFileMissing) ?? false
        updatedAtUTC = try container.decode(Date.self, forKey: .updatedAtUTC)
    }

    var title: String {
        switch envelope.kind {
        case .mood:
            return "Mood"
        case .speak:
            return "Thought"
        case .audio:
            return "Raw voice"
        }
    }

    var statusText: String {
        switch syncState {
        case .saved: return "Saved on watch"
        case .queued: return "Held for later"
        case .sending: return "Sending"
        case .synced: return "On your iPhone"
        case .failed: return lastError ?? "Retry"
        }
    }
}

enum WatchCaptureQueuePolicy {
    static let recentLimit = 20
    static let staleSendingInterval: TimeInterval = 120

    static func recentProjection(from outbox: [WatchRecentCapture]) -> [WatchRecentCapture] {
        Array(outbox.sorted { $0.updatedAtUTC > $1.updatedAtUTC }.prefix(recentLimit))
    }

    static func shouldAttemptTransfer(_ item: WatchRecentCapture, now: Date) -> Bool {
        guard item.syncState != .synced, !item.audioFileMissing else { return false }
        if item.syncState == .sending,
           let lastAttempt = item.lastAttemptAtUTC,
           now.timeIntervalSince(lastAttempt) < staleSendingInterval {
            return false
        }
        if let nextAttempt = item.nextAttemptAtUTC, nextAttempt > now {
            return false
        }
        return true
    }

    static func backoffDelay(forAttempt attempt: Int) -> TimeInterval {
        let exponent = max(0, min(attempt - 1, 7))
        return min(15 * pow(2, Double(exponent)), 30 * 60)
    }
}

struct WatchAudioManifest: Codable, Hashable, Sendable {
    var audioAssetID: UUID
    var captureID: UUID
    var fileName: String
    var duration: TimeInterval
    var codec: String
    var sampleRateHz: Int
    var bitRate: Int
    var byteCount: Int64
    var createdAtUTC: Date

    init(
        audioAssetID: UUID = UUID(),
        captureID: UUID,
        fileName: String,
        duration: TimeInterval,
        codec: String = "aac-lc",
        sampleRateHz: Int = 24_000,
        bitRate: Int = 64_000,
        byteCount: Int64,
        createdAtUTC: Date = Date()
    ) {
        self.audioAssetID = audioAssetID
        self.captureID = captureID
        self.fileName = fileName
        self.duration = duration
        self.codec = codec
        self.sampleRateHz = sampleRateHz
        self.bitRate = bitRate
        self.byteCount = byteCount
        self.createdAtUTC = createdAtUTC
    }
}

struct WatchCaptureEnvelope: Codable, Identifiable, Hashable, Sendable {
    static let schemaVersion = 1
    static let userInfoPayloadKey = "offrecord.watchCapture.payload"
    static let userInfoKindKey = "offrecord.watchCapture.kind"
    static let userInfoCaptureIDKey = "offrecord.watchCapture.captureID"

    var id: UUID { captureID }

    var captureID: UUID
    var schemaVersion: Int
    var kind: WatchCaptureKind
    var createdAtUTC: Date
    var sourceSurface: WatchCaptureSourceSurface
    var privacyMode: String
    var moodValue: String?
    var text: String?
    var textPreview: String?
    var speechTruthState: WatchSpeechTruthState?
    var audioManifest: WatchAudioManifest?

    init(
        captureID: UUID = UUID(),
        schemaVersion: Int = Self.schemaVersion,
        kind: WatchCaptureKind,
        createdAtUTC: Date = Date(),
        sourceSurface: WatchCaptureSourceSurface = .app,
        privacyMode: String = "private",
        moodValue: String? = nil,
        text: String? = nil,
        textPreview: String? = nil,
        speechTruthState: WatchSpeechTruthState? = nil,
        audioManifest: WatchAudioManifest? = nil
    ) {
        self.captureID = captureID
        self.schemaVersion = schemaVersion
        self.kind = kind
        self.createdAtUTC = createdAtUTC
        self.sourceSurface = sourceSurface
        self.privacyMode = privacyMode
        self.moodValue = moodValue
        self.text = text
        self.textPreview = textPreview
        self.speechTruthState = speechTruthState
        self.audioManifest = audioManifest
    }

    var privacySafePreview: String {
        switch kind {
        case .mood:
            return moodValue ?? "Mood"
        case .speak:
            return textPreview?.isEmpty == false ? textPreview! : "Dictated thought"
        case .audio:
            if let duration = audioManifest?.duration {
                return "Audio \(Self.durationFormatter.string(from: duration) ?? "")"
            }
            return "Audio note"
        }
    }

    func userInfoPayload() throws -> [String: Any] {
        [
            Self.userInfoPayloadKey: try JSONEncoder.watchCapture.encode(self),
            Self.userInfoKindKey: kind.rawValue,
            Self.userInfoCaptureIDKey: captureID.uuidString
        ]
    }

    static func decoded(from userInfo: [String: Any]) throws -> WatchCaptureEnvelope {
        guard let data = userInfo[userInfoPayloadKey] as? Data else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: [], debugDescription: "Missing watch capture payload")
            )
        }
        return try JSONDecoder.watchCapture.decode(WatchCaptureEnvelope.self, from: data)
    }

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter
    }()
}

struct WatchCaptureReceipt: Codable, Hashable, Sendable {
    static let userInfoPayloadKey = "offrecord.watchCapture.receipt"
    static let userInfoCaptureIDKey = "offrecord.watchCapture.receipt.captureID"

    var captureID: UUID
    var importedEntryID: UUID
    var importedAtUTC: Date
    var kind: WatchCaptureKind

    func userInfoPayload() throws -> [String: Any] {
        [
            Self.userInfoPayloadKey: try JSONEncoder.watchCapture.encode(self),
            Self.userInfoCaptureIDKey: captureID.uuidString
        ]
    }

    static func decoded(from userInfo: [String: Any]) throws -> WatchCaptureReceipt {
        guard let data = userInfo[userInfoPayloadKey] as? Data else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: [], debugDescription: "Missing watch import receipt payload")
            )
        }
        return try JSONDecoder.watchCapture.decode(WatchCaptureReceipt.self, from: data)
    }
}

extension JSONEncoder {
    static var watchCapture: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var watchCapture: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
