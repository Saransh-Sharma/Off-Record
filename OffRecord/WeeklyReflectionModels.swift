import Foundation

enum WeeklyReflectionProcessingMode: String, Codable, Sendable {
    case local
}

enum WeeklyReflectionStatus: String, Codable, Sendable {
    case ready
    case seen
    case dismissed
    case superseded
    case deleted
    case insufficientData
    case failed
}

enum WeeklyReflectionSafetyLevel: String, Codable, Sendable {
    case none
    case mildDistress
    case moderateConcern
    case highRiskExcluded
}

enum WeeklyReflectionEligibilityKind: String, Codable, Sendable {
    case full
    case light
    case empty
}

enum WeeklyReflectionSourceType: String, Codable, Sendable {
    case text
    case voiceTranscript
    case photoNote
}

struct WeeklyReflectionSettings: Codable, Hashable, Sendable {
    var isEnabled: Bool
    var reminderWeekday: Int
    var reminderHour: Int
    var reminderMinute: Int
    var showHomeCard: Bool
    var sendNotification: Bool

    static let `default` = WeeklyReflectionSettings(
        isEnabled: true,
        reminderWeekday: 1,
        reminderHour: 19,
        reminderMinute: 0,
        showHomeCard: true,
        sendNotification: true
    )
}

struct WeeklyReflectionPeriod: Codable, Hashable, Sendable {
    var start: Date
    var end: Date

    func contains(_ date: Date) -> Bool {
        date >= start && date <= end
    }
}

struct WeeklyReflectionEligibility: Equatable, Sendable {
    let kind: WeeklyReflectionEligibilityKind
    let entryCount: Int
    let wordCount: Int
}

struct WeeklyReflectionEvidenceRef: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let entryId: UUID
    let entryDate: Date
    let sourceType: WeeklyReflectionSourceType
    let quote: String?
    let reason: String?
}

struct WeeklyReflectionTheme: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var title: String
    var summary: String
    var evidenceRefs: [WeeklyReflectionEvidenceRef]
}

struct WeeklyReflectionEmotionalArc: Codable, Hashable, Sendable {
    var label: String
    var description: String
}

struct WeeklyReflectionReport: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let periodStart: Date
    let periodEnd: Date
    var generatedAt: Date
    var versionNumber: Int
    var processingMode: WeeklyReflectionProcessingMode
    var status: WeeklyReflectionStatus
    var eligibility: WeeklyReflectionEligibilityKind
    var includedEntryIds: [UUID]
    var hiddenEntryIds: [UUID]
    var unavailableEntryIds: [UUID]
    var privateEntryCount: Int
    var inputSignature: String
    var heroSentence: String
    var summary: String
    var emotionalArc: WeeklyReflectionEmotionalArc?
    var themes: [WeeklyReflectionTheme]
    var wins: [String]
    var frictions: [String]
    var questions: [String]
    var savedTakeaway: String?
    var safetyLevel: WeeklyReflectionSafetyLevel
    var userMarkedHelpful: Bool?

    var period: WeeklyReflectionPeriod {
        WeeklyReflectionPeriod(start: periodStart, end: periodEnd)
    }

    var isVisibleInHistory: Bool {
        status != .deleted && status != .superseded
    }

    var isVisibleOnHome: Bool {
        switch status {
        case .ready, .seen, .insufficientData, .failed:
            return true
        case .dismissed, .superseded, .deleted:
            return false
        }
    }
}

struct WeeklyReflectionEntrySnapshot: Identifiable, Hashable, Sendable {
    let id: UUID
    let date: Date
    let updatedAt: Date
    let mood: String?
    let text: String
    let wordCount: Int
    let sourceType: WeeklyReflectionSourceType
    let sentiment: Double

    init(id: UUID, date: Date, updatedAt: Date, mood: String?, text: String, sourceType: WeeklyReflectionSourceType) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.id = id
        self.date = date
        self.updatedAt = updatedAt
        self.mood = mood
        self.text = trimmed
        self.wordCount = trimmed.split { $0.isWhitespace || $0.isNewline }.count
        self.sourceType = sourceType
        self.sentiment = ProactiveReflectionAnalyzer.sentimentScore(text: trimmed, mood: mood)
    }

    init?(entry: DiaryEntry) {
        guard let id = entry.id else { return nil }
        let text = (entry.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let date = entry.date ?? entry.createdAt ?? Date()
        let sourceType: WeeklyReflectionSourceType
        if entry.hasStartedEntryAudio {
            sourceType = .voiceTranscript
        } else if entry.hasStartedEntryPhotos {
            sourceType = .photoNote
        } else {
            sourceType = .text
        }
        self.init(
            id: id,
            date: date,
            updatedAt: entry.updatedAt ?? date,
            mood: entry.value(forKey: "mood") as? String,
            text: text,
            sourceType: sourceType
        )
    }
}
