//
//  FridayProfileStore.swift
//  OffRecord
//
//  Where Friday's learned profile lives: a protected JSON file in
//  Application Support/FridayLocal, excluded from backups and never synced.
//  Earlier versions kept it in a CloudKit-synced `AIState` row. The first
//  load moves that row into the file and deletes the row so it stops
//  syncing; a row that arrives later from an older device is deleted too.
//

import CoreData
import Foundation
import os.log

private let profileStoreLogger = Logger(subsystem: "com.singularity.offrecord", category: "FridayProfileStore")

/// Everything Friday has learned, as saved on disk.
struct FridayProfilePayload: Codable {
    var communicationStyle: CommunicationStyle
    var emotionalSignature: EmotionalSignature
    var thoughtPatterns: ThoughtPatterns
    var knowledgeGraph: PersonalKnowledgeGraph
    var behavioralPatterns: BehavioralPatterns
    var summary: FridaySummary
}

@MainActor
struct FridayProfileStore {
    static let fileName = "friday-profile.json"
    /// `AIState.type` values that held the profile before it moved to a local file.
    static let legacyStateTypes = ["friday_assistant", "digital_twin"]

    let file: FridayProtectedJSONFile<FridayProfilePayload>
    let legacyContext: NSManagedObjectContext

    init(directoryURL: URL? = nil, legacyContext: NSManagedObjectContext) {
        self.file = FridayProtectedJSONFile(fileName: Self.fileName, directoryURL: directoryURL)
        self.legacyContext = legacyContext
    }

    /// The saved profile, moving the old synced copy into the local file the first time.
    func load() -> FridayProfilePayload? {
        if let payload = file.load() {
            deleteLegacyRows()
            return payload
        }
        guard let legacy = legacyPayload() else {
            deleteLegacyRows()
            return nil
        }
        file.save(legacy)
        guard file.load() != nil else {
            // Keep the old row until the file is safely written.
            profileStoreLogger.error("Couldn’t write the Friday profile file; keeping the old copy for now.")
            return legacy
        }
        deleteLegacyRows()
        profileStoreLogger.notice("Moved the Friday profile out of synced storage.")
        return legacy
    }

    func save(_ payload: FridayProfilePayload) {
        file.save(payload)
    }

    /// Deletes the file and any old synced copy.
    func delete() {
        file.delete()
        deleteLegacyRows()
    }

    private func legacyPayload() -> FridayProfilePayload? {
        let request = NSFetchRequest<AIState>(entityName: "AIState")
        request.predicate = NSPredicate(format: "type IN %@", Self.legacyStateTypes)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \AIState.updatedAt, ascending: false)]
        let rows = (try? legacyContext.fetch(request)) ?? []
        let decoder = JSONDecoder()
        for row in rows {
            if let data = row.payload, let payload = try? decoder.decode(FridayProfilePayload.self, from: data) {
                return payload
            }
        }
        return nil
    }

    private func deleteLegacyRows() {
        let request = NSFetchRequest<AIState>(entityName: "AIState")
        request.predicate = NSPredicate(format: "type IN %@", Self.legacyStateTypes)
        guard let rows = try? legacyContext.fetch(request), !rows.isEmpty else { return }
        rows.forEach(legacyContext.delete)
        do {
            try legacyContext.save()
        } catch {
            profileStoreLogger.error("Couldn’t delete the old Friday profile row: \(error.localizedDescription, privacy: .public)")
        }
    }
}
