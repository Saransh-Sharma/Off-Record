import CoreData
import Foundation
import os.log

private let audioAttachmentLogger = Logger(subsystem: "com.singularity.offrecord", category: "AudioAttachments")

enum AudioAttachmentStore {
    static let recordingsFolderName = "Recordings"

    static func recordingsDirectory() throws -> URL {
        let fileManager = FileManager.default
        guard let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw NSError(
                domain: "AudioAttachmentStore",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Cannot access Application Support directory."]
            )
        }
        let directory = base.appendingPathComponent(recordingsFolderName, isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    static func destinationURL(for fileName: String) throws -> URL {
        try recordingsDirectory().appendingPathComponent(fileName)
    }

    @discardableResult
    static func attachAudio(
        fileName: String,
        duration: TimeInterval,
        createdAt: Date,
        sourceCaptureID: UUID?,
        byteCount: Int64,
        codec: String,
        to entry: DiaryEntry,
        in context: NSManagedObjectContext
    ) -> NSManagedObject {
        let attachment = NSEntityDescription.insertNewObject(forEntityName: "AudioAttachment", into: context)
        attachment.setValue(UUID(), forKey: "id")
        attachment.setValue(fileName, forKey: "fileName")
        attachment.setValue(createdAt, forKey: "createdAt")
        attachment.setValue(duration, forKey: "duration")
        attachment.setValue(sourceCaptureID, forKey: "sourceCaptureID")
        attachment.setValue(byteCount, forKey: "byteCount")
        attachment.setValue(codec, forKey: "codec")
        attachment.setValue(entry, forKey: "entry")

        if (entry.audioFileName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            entry.audioFileName = fileName
        }
        entry.duration += max(0, duration)
        entry.updatedAt = Date()
        return attachment
    }

    static func audioAttachments(for entry: DiaryEntry) -> [NSManagedObject] {
        let attachments = ((entry.value(forKey: "audioAttachments") as? Set<NSManagedObject>) ?? []).filter { !$0.isDeleted }
        return attachments.sorted {
            let lhsDate = $0.value(forKey: "createdAt") as? Date ?? .distantPast
            let rhsDate = $1.value(forKey: "createdAt") as? Date ?? .distantPast
            if lhsDate != rhsDate { return lhsDate < rhsDate }
            let lhsID = ($0.value(forKey: "id") as? UUID)?.uuidString ?? $0.objectID.uriRepresentation().absoluteString
            let rhsID = ($1.value(forKey: "id") as? UUID)?.uuidString ?? $1.objectID.uriRepresentation().absoluteString
            return lhsID < rhsID
        }
    }

    static func audioAttachment(id: UUID, in context: NSManagedObjectContext) -> NSManagedObject? {
        guard NSEntityDescription.entity(forEntityName: "AudioAttachment", in: context) != nil else {
            return nil
        }
        let request = NSFetchRequest<NSManagedObject>(entityName: "AudioAttachment")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    static func audioAttachment(sourceCaptureID: UUID, in context: NSManagedObjectContext) -> NSManagedObject? {
        guard NSEntityDescription.entity(forEntityName: "AudioAttachment", in: context) != nil else {
            return nil
        }
        let request = NSFetchRequest<NSManagedObject>(entityName: "AudioAttachment")
        request.predicate = NSPredicate(format: "sourceCaptureID == %@", sourceCaptureID as CVarArg)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    static func audioURL(for attachment: NSManagedObject) -> URL? {
        guard let fileName = attachment.value(forKey: "fileName") as? String, !fileName.isEmpty,
              let directory = try? recordingsDirectory() else {
            return nil
        }
        return directory.appendingPathComponent(fileName)
    }

    static func attachmentExists(sourceCaptureID: UUID, in context: NSManagedObjectContext) throws -> Bool {
        guard NSEntityDescription.entity(forEntityName: "AudioAttachment", in: context) != nil else {
            return false
        }
        let request = NSFetchRequest<NSManagedObject>(entityName: "AudioAttachment")
        request.predicate = NSPredicate(format: "sourceCaptureID == %@", sourceCaptureID as CVarArg)
        request.fetchLimit = 1
        request.includesPropertyValues = false
        return try context.count(for: request) > 0
    }

    static func audioFileNames(in context: NSManagedObjectContext) -> Set<String> {
        var names = Set<String>()

        let entryRequest = NSFetchRequest<NSDictionary>(entityName: "DiaryEntry")
        entryRequest.propertiesToFetch = ["audioFileName"]
        entryRequest.resultType = .dictionaryResultType
        if let rows = try? context.fetch(entryRequest) {
            for row in rows {
                if let name = row["audioFileName"] as? String, !name.isEmpty {
                    names.insert(name)
                }
            }
        }

        guard NSEntityDescription.entity(forEntityName: "AudioAttachment", in: context) != nil else {
            return names
        }

        let attachmentRequest = NSFetchRequest<NSDictionary>(entityName: "AudioAttachment")
        attachmentRequest.propertiesToFetch = ["fileName"]
        attachmentRequest.resultType = .dictionaryResultType
        do {
            let rows = try context.fetch(attachmentRequest)
            for row in rows {
                if let name = row["fileName"] as? String, !name.isEmpty {
                    names.insert(name)
                }
            }
        } catch {
            audioAttachmentLogger.warning("Unable to fetch audio attachment file names: \(error.localizedDescription, privacy: .public)")
        }

        return names
    }

    static func audioURLs(for entry: DiaryEntry) -> [URL] {
        let legacyName = (entry.audioFileName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var rows: [(date: Date, fileName: String)] = []

        if !legacyName.isEmpty {
            rows.append((entry.createdAt ?? entry.date ?? Date.distantPast, legacyName))
        }

        for attachment in audioAttachments(for: entry) {
            guard let fileName = attachment.value(forKey: "fileName") as? String, !fileName.isEmpty else { continue }
            if fileName == legacyName { continue }
            let createdAt = attachment.value(forKey: "createdAt") as? Date ?? Date.distantPast
            rows.append((createdAt, fileName))
        }

        guard let directory = try? recordingsDirectory() else { return [] }
        return rows
            .sorted { $0.date < $1.date }
            .map { directory.appendingPathComponent($0.fileName) }
    }
}
