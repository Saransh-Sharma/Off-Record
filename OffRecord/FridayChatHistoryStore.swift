//
//  FridayChatHistoryStore.swift
//  OffRecord
//
//  Local-only persistence for the Friday conversation. The thread is kept as
//  JSON in Application Support with complete file protection and excluded
//  from iCloud backup — the same privacy posture as Friday's AI state. It is
//  never sent anywhere.
//
//  Citations are stored as entry references (entry ID, match reason, and the
//  snippet that was already on screen). On restore they are re-resolved
//  against the journal: citations whose entries were deleted are dropped,
//  along with any observation that only quoted those entries.
//

import Foundation
import os

private let fridayHistoryLogger = Logger(subsystem: "com.singularity.offrecord", category: "FridayChatHistory")

// MARK: - Protected JSON file

/// A small JSON document in Application Support, written atomically with
/// `.completeFileProtection` and excluded from device backups.
struct FridayProtectedJSONFile<Value: Codable> {
    let fileName: String

    private static var directoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("FridayLocal", isDirectory: true)
    }

    var url: URL { Self.directoryURL.appendingPathComponent(fileName) }

    func load() -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(Value.self, from: data)
        } catch {
            fridayHistoryLogger.error("Could not decode \(fileName, privacy: .public); starting fresh.")
            return nil
        }
    }

    func save(_ value: Value) {
        do {
            try prepareDirectory()
            let data = try JSONEncoder().encode(value)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            var fileURL = url
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? fileURL.setResourceValues(values)
        } catch {
            fridayHistoryLogger.error("Could not save \(fileName, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    func delete() {
        try? FileManager.default.removeItem(at: url)
    }

    private func prepareDirectory() throws {
        var directory = Self.directoryURL
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete]
            )
        }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? directory.setResourceValues(values)
    }
}

// MARK: - Stored shapes

struct FridayStoredCitation: Codable, Equatable {
    let id: String
    let entryID: UUID
    let snippet: String
    let matchReason: String
    let score: Double
}

struct FridayStoredObservation: Codable, Equatable {
    let text: String
    let evidenceIDs: [String]
}

struct FridayStoredFollowUp: Codable, Equatable {
    let title: String
    let prompt: String
    let questionID: String?
}

struct FridayStoredMessage: Codable, Equatable {
    let id: UUID
    let isUser: Bool
    let timestamp: Date
    let summary: String
    let observations: [FridayStoredObservation]
    let citations: [FridayStoredCitation]
    let confidence: Double?
    let limitations: String?
    let followUps: [FridayStoredFollowUp]
}

struct FridayStoredThread: Codable {
    var version = 1
    var messages: [FridayStoredMessage]
}

// MARK: - Store

@MainActor
enum FridayChatHistoryStore {
    /// Keeps the file small; older turns roll off.
    static let maximumStoredMessages = 120

    private static let file = FridayProtectedJSONFile<FridayStoredThread>(fileName: "friday-conversation.json")

    /// UI tests start from a clean landing screen every launch and never touch disk.
    private static var isEphemeral: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITesting")
    }

    static func load(resolving entryProvider: (UUID) -> DiaryEntry?) -> [FridayChatMessage] {
        guard !isEphemeral, let thread = file.load() else { return [] }
        return thread.messages.compactMap { restore($0, entryProvider: entryProvider) }
    }

    static func save(_ messages: [FridayChatMessage]) {
        guard !isEphemeral else { return }
        guard !messages.isEmpty else {
            file.delete()
            return
        }
        let stored = messages.suffix(maximumStoredMessages).map(store)
        file.save(FridayStoredThread(messages: Array(stored)))
    }

    static func clear() {
        file.delete()
    }

    // MARK: Mapping

    private static func store(_ message: FridayChatMessage) -> FridayStoredMessage {
        FridayStoredMessage(
            id: message.id,
            isUser: message.isUser,
            timestamp: message.timestamp,
            summary: message.summary,
            observations: message.observations.map { FridayStoredObservation(text: $0.text, evidenceIDs: $0.evidenceIDs) },
            citations: message.evidence.map {
                FridayStoredCitation(
                    id: $0.id,
                    entryID: $0.entryID,
                    snippet: $0.snippet,
                    matchReason: $0.matchReason.rawValue,
                    score: $0.score
                )
            },
            confidence: message.confidence,
            limitations: message.limitations,
            followUps: message.followUps.map { FridayStoredFollowUp(title: $0.title, prompt: $0.prompt, questionID: $0.question?.rawValue) }
        )
    }

    private static func restore(_ stored: FridayStoredMessage, entryProvider: (UUID) -> DiaryEntry?) -> FridayChatMessage? {
        if stored.isUser {
            return FridayChatMessage(id: stored.id, timestamp: stored.timestamp, text: stored.summary, isUser: true)
        }

        // Re-resolve every citation against the live journal.
        let evidence: [EvidenceReference] = stored.citations.compactMap { citation in
            guard let entry = entryProvider(citation.entryID) else { return nil }
            let date = entry.date ?? entry.createdAt ?? stored.timestamp
            let mood = entry.value(forKey: "mood") as? String
            return EvidenceReference(
                id: citation.id,
                entryID: citation.entryID,
                date: date,
                mood: mood,
                snippet: citation.snippet,
                chunkText: citation.snippet,
                score: citation.score,
                matchReason: EvidenceReference.MatchReason(rawValue: citation.matchReason) ?? .meaning
            )
        }
        let liveIDs = Set(evidence.map(\.id))
        let droppedAny = evidence.count < stored.citations.count

        // An observation that only cited deleted entries may quote them — drop it.
        let observations: [EvidenceObservation] = stored.observations.compactMap { observation in
            guard !observation.evidenceIDs.isEmpty else {
                return EvidenceObservation(text: observation.text, evidenceIDs: [])
            }
            let remaining = observation.evidenceIDs.filter { liveIDs.contains($0) }
            guard !remaining.isEmpty else { return nil }
            return EvidenceObservation(text: observation.text, evidenceIDs: remaining)
        }

        var limitations = stored.limitations
        if droppedAny {
            let note = evidence.isEmpty
                ? "The entries behind this answer have since been deleted."
                : "Some entries behind this answer have since been deleted."
            limitations = [limitations, note].compactMap { $0 }.joined(separator: " ")
        }

        return FridayChatMessage(
            id: stored.id,
            timestamp: stored.timestamp,
            summary: stored.summary,
            isUser: false,
            evidence: evidence,
            observations: observations,
            confidence: stored.confidence,
            limitations: limitations,
            followUps: stored.followUps.map {
                FridayFollowUp(title: $0.title, prompt: $0.prompt, question: $0.questionID.flatMap(FridayQuestion.init(rawValue:)))
            }
        )
    }
}
