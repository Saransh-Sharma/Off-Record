//
//  BackupService.swift
//  OffRecord
//
//  Handles data backup and export functionality.
//  Supports JSON export/import and plain text export.
//  All data remains on-device or in user-controlled locations.
//

import Foundation
import CoreData
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Backup Data Models

/// Represents a synced photo attachment for export/import.
struct ExportablePhotoAttachment: Codable, Identifiable {
    let id: UUID
    let createdAt: Date
    let sortOrder: Int32
    let imageData: Data
    let fileName: String?
    let mimeType: String?

    init(from attachment: PhotoAttachment) {
        self.id = attachment.id ?? UUID()
        self.createdAt = attachment.createdAt ?? Date()
        self.sortOrder = attachment.sortOrder
        self.imageData = attachment.imageData ?? Data()
        self.fileName = attachment.fileName
        self.mimeType = attachment.mimeType
    }
}

/// Represents an audio attachment record for export/import.
struct ExportableAudioAttachment: Codable, Identifiable {
    let id: UUID
    let fileName: String
    let createdAt: Date
    let duration: TimeInterval
    let sourceCaptureID: UUID?
    let byteCount: Int64
    let codec: String?
    let audioData: Data?

    init(from attachment: NSManagedObject) {
        self.id = attachment.value(forKey: "id") as? UUID ?? UUID()
        self.fileName = attachment.value(forKey: "fileName") as? String ?? ""
        self.createdAt = attachment.value(forKey: "createdAt") as? Date ?? Date()
        self.duration = attachment.value(forKey: "duration") as? TimeInterval ?? 0
        self.sourceCaptureID = attachment.value(forKey: "sourceCaptureID") as? UUID
        self.byteCount = attachment.value(forKey: "byteCount") as? Int64 ?? 0
        self.codec = attachment.value(forKey: "codec") as? String
        self.audioData = nil
    }

    private init(
        id: UUID,
        fileName: String,
        createdAt: Date,
        duration: TimeInterval,
        sourceCaptureID: UUID?,
        byteCount: Int64,
        codec: String?,
        audioData: Data?
    ) {
        self.id = id
        self.fileName = fileName
        self.createdAt = createdAt
        self.duration = duration
        self.sourceCaptureID = sourceCaptureID
        self.byteCount = byteCount
        self.codec = codec
        self.audioData = audioData
    }

    func embeddingAudioPayload() -> ExportableAudioAttachment {
        guard audioData == nil,
              let url = try? AudioAttachmentStore.destinationURL(for: fileName),
              let data = try? Data(contentsOf: url) else {
            return self
        }
        return ExportableAudioAttachment(
            id: id,
            fileName: fileName,
            createdAt: createdAt,
            duration: duration,
            sourceCaptureID: sourceCaptureID,
            byteCount: byteCount,
            codec: codec,
            audioData: data
        )
    }
}

struct ExportableJournalBlock: Codable, Identifiable {
    let id: UUID
    let kind: String
    let createdAt: Date
    let updatedAt: Date
    let sortOrder: Int32
    let text: String?
    let mood: String?
    let duration: Double
    let sourceCaptureID: UUID?
    let audioAttachmentID: UUID?
    let photoAttachmentID: UUID?

    init(from block: JournalBlock) {
        self.id = block.blockID
        self.kind = block.blockKind?.rawValue ?? ""
        self.createdAt = block.blockCreatedAt == .distantPast ? Date() : block.blockCreatedAt
        self.updatedAt = block.blockUpdatedAt
        self.sortOrder = block.blockSortOrder
        self.text = block.textValue.isEmpty ? nil : block.textValue
        self.mood = block.moodValue.isEmpty ? nil : block.moodValue
        self.duration = block.durationValue
        self.sourceCaptureID = block.sourceCaptureIDValue
        self.audioAttachmentID = block.audioAttachmentIDValue
        self.photoAttachmentID = block.photoAttachmentIDValue
    }
}

/// Represents a single diary entry for export/import
struct ExportableEntry: Codable, Identifiable {
    let id: UUID
    let date: Date
    let text: String
    let mood: String?
    let isStarred: Bool
    let createdAt: Date
    let updatedAt: Date
    let audioFileName: String?
    let duration: TimeInterval?
    let audioAttachments: [ExportableAudioAttachment]?
    let blocks: [ExportableJournalBlock]?
    let photoFileNames: String?
    let photos: [ExportablePhotoAttachment]

    init(from entry: DiaryEntry) {
        self.id = entry.id ?? UUID()
        self.date = entry.date ?? Date()
        self.text = entry.text ?? ""
        self.mood = entry.value(forKey: "mood") as? String
        self.isStarred = entry.isStarred
        self.createdAt = entry.createdAt ?? Date()
        self.updatedAt = entry.updatedAt ?? Date()
        self.audioFileName = entry.audioFileName
        self.duration = entry.duration
        let audioRows = ((entry.value(forKey: "audioAttachments") as? Set<NSManagedObject>) ?? [])
            .map { ExportableAudioAttachment(from: $0) }
            .filter { !$0.fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.createdAt < $1.createdAt }
        self.audioAttachments = audioRows.isEmpty ? nil : audioRows
        let blockRows = (((entry.value(forKey: "blocks") as? Set<JournalBlock>) ?? [])
            .filter { !$0.isDeleted }
            .sorted {
                if $0.blockCreatedAt != $1.blockCreatedAt { return $0.blockCreatedAt < $1.blockCreatedAt }
                if $0.blockSortOrder != $1.blockSortOrder { return $0.blockSortOrder < $1.blockSortOrder }
                return $0.blockID.uuidString < $1.blockID.uuidString
            })
            .map { ExportableJournalBlock(from: $0) }
        self.blocks = blockRows.isEmpty ? nil : blockRows
        self.photoFileNames = entry.value(forKey: "photoFileNames") as? String
        self.photos = PhotoStorageManager.shared.attachments(for: entry).map { ExportablePhotoAttachment(from: $0) }
    }

    private init(
        id: UUID,
        date: Date,
        text: String,
        mood: String?,
        isStarred: Bool,
        createdAt: Date,
        updatedAt: Date,
        audioFileName: String?,
        duration: TimeInterval?,
        audioAttachments: [ExportableAudioAttachment]?,
        blocks: [ExportableJournalBlock]?,
        photoFileNames: String?,
        photos: [ExportablePhotoAttachment]
    ) {
        self.id = id
        self.date = date
        self.text = text
        self.mood = mood
        self.isStarred = isStarred
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.audioFileName = audioFileName
        self.duration = duration
        self.audioAttachments = audioAttachments
        self.blocks = blocks
        self.photoFileNames = photoFileNames
        self.photos = photos
    }

    func embeddingAudioPayloads() -> ExportableEntry {
        ExportableEntry(
            id: id,
            date: date,
            text: text,
            mood: mood,
            isStarred: isStarred,
            createdAt: createdAt,
            updatedAt: updatedAt,
            audioFileName: audioFileName,
            duration: duration,
            audioAttachments: audioAttachments?.map { $0.embeddingAudioPayload() },
            blocks: blocks,
            photoFileNames: photoFileNames,
            photos: photos
        )
    }
}

/// Container for full backup data
struct BackupData: Codable {
    let version: String
    let exportDate: Date
    let deviceName: String
    let entryCount: Int
    let entries: [ExportableEntry]
    
    init(entries: [ExportableEntry]) {
        self.init(entries: entries, deviceName: BackupData.currentDeviceName())
    }

    init(entries: [ExportableEntry], deviceName: String) {
        self.version = "1.0"
        self.exportDate = Date()
        self.deviceName = deviceName
        self.entryCount = entries.count
        self.entries = entries
    }

    static func currentDeviceName() -> String {
        #if canImport(UIKit)
        UIDevice.current.name
        #else
        Host.current().localizedName ?? "Mac"
        #endif
    }
}

private func backupFormattedDate() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: Date())
}

private func backupFormattedFullDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .full
    formatter.timeStyle = .short
    return formatter.string(from: date)
}

private func backupMoodToEmoji(_ mood: String) -> String {
    switch mood.lowercased() {
    case "happy": return "☀️"
    case "calm": return "🍃"
    case "grateful": return "💗"
    case "excited": return "⭐"
    case "tired": return "🌙"
    case "anxious": return "💨"
    case "sad": return "🌧️"
    case "angry": return "🔥"
    default: return "📝"
    }
}

// MARK: - Backup Service

@MainActor
final class BackupService {
    static let shared = BackupService()
    
    private init() {}
    
    // MARK: - JSON Export
    
    /// Export all entries to JSON format
    func exportToJSON(entries: [DiaryEntry]) throws -> URL {
        let exportableEntries = entries.map { ExportableEntry(from: $0) }
        return try Self.writeJSONBackup(entries: exportableEntries, deviceName: BackupData.currentDeviceName())
    }

    nonisolated static func writeJSONBackup(entries: [ExportableEntry], deviceName: String) throws -> URL {
        let backupData = BackupData(entries: entries.map { $0.embeddingAudioPayloads() }, deviceName: deviceName)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        let jsonData = try encoder.encode(backupData)
        
        // Create temp file
        let fileName = "offrecord_backup_\(backupFormattedDate()).json"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        try jsonData.write(to: tempURL)
        
        return tempURL
    }

    nonisolated static func writeEncryptedBackup(entries: [ExportableEntry], password: String, deviceName: String) throws -> URL {
        let backupData = BackupData(entries: entries.map { $0.embeddingAudioPayloads() }, deviceName: deviceName)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]

        let jsonData = try encoder.encode(backupData)
        let encryptedData = try EncryptionService.encrypt(data: jsonData, password: password)

        let fileName = "offrecord_backup_\(backupFormattedDate()).dvx"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try encryptedData.write(to: tempURL)

        return tempURL
    }

    nonisolated static func writeTextExport(entries: [ExportableEntry]) throws -> URL {
        var textContent = """
        ═══════════════════════════════════════════════════════════════
                              DAILYVOX DIARY EXPORT
        ═══════════════════════════════════════════════════════════════

        Exported: \(backupFormattedFullDate(Date()))
        Total Entries: \(entries.count)

        ═══════════════════════════════════════════════════════════════

        """

        let sortedEntries = entries.sorted { $0.date > $1.date }
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .full
        dateFormatter.timeStyle = .short

        for entry in sortedEntries {
            let starred = entry.isStarred ? " ⭐" : ""
            textContent += """
            ───────────────────────────────────────────────────────────────
            📅 \(dateFormatter.string(from: entry.date))\(starred)
            """

            if let mood = entry.mood, !mood.isEmpty {
                textContent += "\n\(backupMoodToEmoji(mood)) Mood: \(mood.capitalized)"
            }

            textContent += """

            ───────────────────────────────────────────────────────────────

            \(entry.text.isEmpty ? "(No text)" : entry.text)


            """
        }

        textContent += """
        ═══════════════════════════════════════════════════════════════
                              END OF EXPORT
        ═══════════════════════════════════════════════════════════════
        """

        let fileName = "offrecord_diary_\(backupFormattedDate()).txt"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try textContent.write(to: tempURL, atomically: true, encoding: .utf8)
        return tempURL
    }

    nonisolated static func writeMarkdownExport(entries: [ExportableEntry]) throws -> URL {
        var mdContent = """
        # OffRecord AI Journal Export

        **Exported:** \(backupFormattedFullDate(Date()))
        **Total Entries:** \(entries.count)

        ---

        """

        let sortedEntries = entries.sorted { $0.date > $1.date }
        let groupedByMonth = Dictionary(grouping: sortedEntries) { entry -> String in
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: entry.date)
        }

        let sortedMonths = groupedByMonth.keys.sorted { month1, month2 in
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM yyyy"
            let date1 = formatter.date(from: month1) ?? Date()
            let date2 = formatter.date(from: month2) ?? Date()
            return date1 > date2
        }

        for month in sortedMonths {
            mdContent += "## \(month)\n\n"
            for entry in groupedByMonth[month] ?? [] {
                let dayFormatter = DateFormatter()
                dayFormatter.dateFormat = "EEEE, MMMM d"
                let starred = entry.isStarred ? " ⭐" : ""
                mdContent += "### \(dayFormatter.string(from: entry.date))\(starred)\n\n"
                if let mood = entry.mood, !mood.isEmpty {
                    mdContent += "**Mood:** \(mood.capitalized)\n\n"
                }
                mdContent += "\(entry.text.isEmpty ? "(No text)" : entry.text)\n\n---\n\n"
            }
        }

        let fileName = "offrecord_diary_\(backupFormattedDate()).md"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try mdContent.write(to: tempURL, atomically: true, encoding: .utf8)
        return tempURL
    }

    nonisolated static func writeCSVExport(entries: [ExportableEntry]) throws -> URL {
        var csvContent = "Date,Time,Mood,Starred,Word Count,Text\n"

        let sortedEntries = entries.sorted { $0.date > $1.date }
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"

        for entry in sortedEntries {
            let text = entry.text.replacingOccurrences(of: "\"", with: "\"\"")
            let mood = entry.mood ?? ""
            let starred = entry.isStarred ? "Yes" : "No"
            let wordCount = text.split { $0.isWhitespace || $0.isNewline }.count
            let escapedText = "\"\(text.replacingOccurrences(of: "\n", with: " "))\""
            csvContent += "\(dateFormatter.string(from: entry.date)),\(timeFormatter.string(from: entry.date)),\(mood),\(starred),\(wordCount),\(escapedText)\n"
        }

        let fileName = "offrecord_entries_\(backupFormattedDate()).csv"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try csvContent.write(to: tempURL, atomically: true, encoding: .utf8)
        return tempURL
    }
    
    /// Export selected entries to JSON
    func exportToJSON(entries: [DiaryEntry], startDate: Date?, endDate: Date?, starredOnly: Bool) throws -> URL {
        var filteredEntries = entries
        
        if let start = startDate {
            filteredEntries = filteredEntries.filter { ($0.date ?? Date.distantPast) >= start }
        }
        
        if let end = endDate {
            filteredEntries = filteredEntries.filter { ($0.date ?? Date.distantFuture) <= end }
        }
        
        if starredOnly {
            filteredEntries = filteredEntries.filter { $0.isStarred }
        }
        
        return try exportToJSON(entries: filteredEntries)
    }
    
    // MARK: - JSON Import
    
    /// Import entries from JSON backup
    func importFromJSON(url: URL, context: NSManagedObjectContext) throws -> Int {
        let data = try Data(contentsOf: url)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let backupData = try decoder.decode(BackupData.self, from: data)
        
        var importedCount = 0
        
        for exportedEntry in backupData.entries {
            // Check if entry already exists
            let fetchRequest: NSFetchRequest<DiaryEntry> = DiaryEntry.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", exportedEntry.id as CVarArg)
            
            let existingEntries = try context.fetch(fetchRequest)
            
            if existingEntries.isEmpty {
                // Create new entry
                let newEntry = DiaryEntry(context: context)
                newEntry.id = exportedEntry.id
                newEntry.date = exportedEntry.date
                newEntry.text = exportedEntry.text
                newEntry.setValue(exportedEntry.mood, forKey: "mood")
                newEntry.isStarred = exportedEntry.isStarred
                newEntry.createdAt = exportedEntry.createdAt
                newEntry.updatedAt = exportedEntry.updatedAt
                newEntry.audioFileName = Self.validatedAudioFileName(exportedEntry.audioFileName)
                newEntry.duration = exportedEntry.duration ?? 0
                newEntry.setValue(exportedEntry.photoFileNames, forKey: "photoFileNames")
                importAudioAttachments(exportedEntry.audioAttachments ?? [], into: newEntry, context: context)
                importPhotos(exportedEntry.photos, into: newEntry, context: context)
                importJournalBlocks(exportedEntry.blocks ?? [], into: newEntry, context: context)
                JournalBlockTimelineStore.backfillBlocksIfNeeded(for: newEntry, in: context)
                JournalBlockTimelineStore.recomposeLegacyFields(for: newEntry, touchUpdatedAt: false)
                newEntry.updatedAt = exportedEntry.updatedAt

                importedCount += 1
            }
        }

        if importedCount > 0 {
            try context.save()
        }

        return importedCount
    }

    // MARK: - Plain Text Export
    
    /// Export entries to plain text format
    func exportToText(entries: [DiaryEntry]) throws -> URL {
        var textContent = """
        ═══════════════════════════════════════════════════════════════
                              DAILYVOX DIARY EXPORT
        ═══════════════════════════════════════════════════════════════
        
        Exported: \(formattedFullDate(Date()))
        Total Entries: \(entries.count)
        
        ═══════════════════════════════════════════════════════════════
        
        """
        
        let sortedEntries = entries.sorted { ($0.date ?? Date()) > ($1.date ?? Date()) }
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .full
        dateFormatter.timeStyle = .short
        
        for entry in sortedEntries {
            let date = entry.date ?? Date()
            let text = entry.text ?? "(No text)"
            let mood = entry.value(forKey: "mood") as? String ?? ""
            let starred = entry.isStarred ? " ⭐" : ""
            
            textContent += """
            ───────────────────────────────────────────────────────────────
            📅 \(dateFormatter.string(from: date))\(starred)
            """
            
            if !mood.isEmpty {
                let moodEmoji = moodToEmoji(mood)
                textContent += "\n\(moodEmoji) Mood: \(mood.capitalized)"
            }
            
            textContent += """
            
            ───────────────────────────────────────────────────────────────
            
            \(text)
            
            
            """
        }
        
        textContent += """
        ═══════════════════════════════════════════════════════════════
                              END OF EXPORT
        ═══════════════════════════════════════════════════════════════
        """
        
        // Create temp file
        let fileName = "offrecord_diary_\(formattedDate()).txt"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        try textContent.write(to: tempURL, atomically: true, encoding: .utf8)
        
        return tempURL
    }
    
    /// Export selected entries to plain text
    func exportToText(entries: [DiaryEntry], startDate: Date?, endDate: Date?, starredOnly: Bool) throws -> URL {
        var filteredEntries = Array(entries)
        
        if let start = startDate {
            filteredEntries = filteredEntries.filter { ($0.date ?? Date.distantPast) >= start }
        }
        
        if let end = endDate {
            filteredEntries = filteredEntries.filter { ($0.date ?? Date.distantFuture) <= end }
        }
        
        if starredOnly {
            filteredEntries = filteredEntries.filter { $0.isStarred }
        }
        
        return try exportToText(entries: filteredEntries)
    }
    
    // MARK: - Markdown Export
    
    /// Export entries to Markdown format
    func exportToMarkdown(entries: [DiaryEntry]) throws -> URL {
        var mdContent = """
        # OffRecord AI Journal Export
        
        **Exported:** \(formattedFullDate(Date()))  
        **Total Entries:** \(entries.count)
        
        ---
        
        """
        
        let sortedEntries = entries.sorted { ($0.date ?? Date()) > ($1.date ?? Date()) }
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .full
        
        let groupedByMonth = Dictionary(grouping: sortedEntries) { entry -> String in
            let date = entry.date ?? Date()
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: date)
        }
        
        let sortedMonths = groupedByMonth.keys.sorted { month1, month2 in
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM yyyy"
            let date1 = formatter.date(from: month1) ?? Date()
            let date2 = formatter.date(from: month2) ?? Date()
            return date1 > date2
        }
        
        for month in sortedMonths {
            mdContent += "## \(month)\n\n"
            
            if let monthEntries = groupedByMonth[month] {
                for entry in monthEntries {
                    let date = entry.date ?? Date()
                    let text = entry.text ?? "(No text)"
                    let mood = entry.value(forKey: "mood") as? String ?? ""
                    let starred = entry.isStarred ? " ⭐" : ""
                    
                    let dayFormatter = DateFormatter()
                    dayFormatter.dateFormat = "EEEE, MMMM d"
                    
                    mdContent += "### \(dayFormatter.string(from: date))\(starred)\n\n"
                    
                    if !mood.isEmpty {
                        mdContent += "**Mood:** \(mood.capitalized)\n\n"
                    }
                    
                    mdContent += "\(text)\n\n---\n\n"
                }
            }
        }
        
        // Create temp file
        let fileName = "offrecord_diary_\(formattedDate()).md"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        try mdContent.write(to: tempURL, atomically: true, encoding: .utf8)
        
        return tempURL
    }
    
    // MARK: - CSV Export
    
    /// Export entries to CSV format
    func exportToCSV(entries: [DiaryEntry]) throws -> URL {
        var csvContent = "Date,Time,Mood,Starred,Word Count,Text\n"
        
        let sortedEntries = entries.sorted { ($0.date ?? Date()) > ($1.date ?? Date()) }
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        
        for entry in sortedEntries {
            let date = entry.date ?? Date()
            let text = (entry.text ?? "").replacingOccurrences(of: "\"", with: "\"\"")
            let mood = entry.value(forKey: "mood") as? String ?? ""
            let starred = entry.isStarred ? "Yes" : "No"
            let wordCount = text.split { $0.isWhitespace || $0.isNewline }.count
            
            // Escape text for CSV
            let escapedText = "\"\(text.replacingOccurrences(of: "\n", with: " "))\""
            
            csvContent += "\(dateFormatter.string(from: date)),\(timeFormatter.string(from: date)),\(mood),\(starred),\(wordCount),\(escapedText)\n"
        }
        
        // Create temp file
        let fileName = "offrecord_entries_\(formattedDate()).csv"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        try csvContent.write(to: tempURL, atomically: true, encoding: .utf8)
        
        return tempURL
    }
    
    // MARK: - Encrypted Export

    /// Export all entries as an encrypted .dvx file
    func exportEncrypted(entries: [DiaryEntry], password: String) throws -> URL {
        let exportableEntries = entries.map { ExportableEntry(from: $0) }
        return try Self.writeEncryptedBackup(entries: exportableEntries, password: password, deviceName: BackupData.currentDeviceName())
    }

    /// Import entries from an encrypted .dvx file
    func importEncrypted(url: URL, password: String, context: NSManagedObjectContext) throws -> Int {
        let encryptedData = try Data(contentsOf: url)
        let jsonData = try EncryptionService.decrypt(data: encryptedData, password: password)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let backupData = try decoder.decode(BackupData.self, from: jsonData)

        var importedCount = 0

        for exportedEntry in backupData.entries {
            let fetchRequest: NSFetchRequest<DiaryEntry> = DiaryEntry.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", exportedEntry.id as CVarArg)

            let existingEntries = try context.fetch(fetchRequest)

            if existingEntries.isEmpty {
                let newEntry = DiaryEntry(context: context)
                newEntry.id = exportedEntry.id
                newEntry.date = exportedEntry.date
                newEntry.text = exportedEntry.text
                newEntry.setValue(exportedEntry.mood, forKey: "mood")
                newEntry.isStarred = exportedEntry.isStarred
                newEntry.createdAt = exportedEntry.createdAt
                newEntry.updatedAt = exportedEntry.updatedAt
                newEntry.audioFileName = Self.validatedAudioFileName(exportedEntry.audioFileName)
                newEntry.duration = exportedEntry.duration ?? 0
                newEntry.setValue(exportedEntry.photoFileNames, forKey: "photoFileNames")
                importAudioAttachments(exportedEntry.audioAttachments ?? [], into: newEntry, context: context)
                importPhotos(exportedEntry.photos, into: newEntry, context: context)
                importJournalBlocks(exportedEntry.blocks ?? [], into: newEntry, context: context)
                JournalBlockTimelineStore.backfillBlocksIfNeeded(for: newEntry, in: context)
                JournalBlockTimelineStore.recomposeLegacyFields(for: newEntry, touchUpdatedAt: false)
                newEntry.updatedAt = exportedEntry.updatedAt

                importedCount += 1
            }
        }

        if importedCount > 0 {
            try context.save()
        }

        return importedCount
    }

    // MARK: - Helpers

    private static func validatedAudioFileName(_ fileName: String?) -> String? {
        guard let fileName else { return nil }
        return try? AudioAttachmentStore.validatedFileName(fileName)
    }

    private func importAudioAttachments(_ attachments: [ExportableAudioAttachment], into entry: DiaryEntry, context: NSManagedObjectContext) {
        guard NSEntityDescription.entity(forEntityName: "AudioAttachment", in: context) != nil else {
            return
        }

        for audio in attachments where !audio.fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let safeName = try? AudioAttachmentStore.validatedFileName(audio.fileName) else {
                continue
            }
            if let audioData = audio.audioData, !audioData.isEmpty {
                do {
                    let destinationURL = try AudioAttachmentStore.destinationURL(for: safeName)
                    try audioData.write(to: destinationURL, options: [.atomic])
                } catch {
                    continue
                }
            }
            let attachment = NSEntityDescription.insertNewObject(forEntityName: "AudioAttachment", into: context)
            attachment.setValue(audio.id, forKey: "id")
            attachment.setValue(safeName, forKey: "fileName")
            attachment.setValue(audio.createdAt, forKey: "createdAt")
            attachment.setValue(audio.duration, forKey: "duration")
            attachment.setValue(audio.sourceCaptureID, forKey: "sourceCaptureID")
            attachment.setValue(audio.byteCount, forKey: "byteCount")
            attachment.setValue(audio.codec, forKey: "codec")
            attachment.setValue(entry, forKey: "entry")
        }
    }

    private func importPhotos(_ photos: [ExportablePhotoAttachment], into entry: DiaryEntry, context: NSManagedObjectContext) {
        for photo in photos where !photo.imageData.isEmpty {
            let attachment = PhotoAttachment(context: context)
            attachment.id = photo.id
            attachment.createdAt = photo.createdAt
            attachment.sortOrder = photo.sortOrder
            attachment.imageData = photo.imageData
            attachment.fileName = photo.fileName
            attachment.mimeType = photo.mimeType ?? "image/jpeg"
            attachment.entry = entry
        }
    }

    private func importJournalBlocks(_ blocks: [ExportableJournalBlock], into entry: DiaryEntry, context: NSManagedObjectContext) {
        guard NSEntityDescription.entity(forEntityName: "JournalBlock", in: context) != nil else {
            return
        }

        let existingIDs = Set(JournalBlockTimelineStore.blocks(for: entry).map(\.blockID))
        for block in blocks {
            guard !existingIDs.contains(block.id) else { continue }
            let imported = NSEntityDescription.insertNewObject(forEntityName: "JournalBlock", into: context) as! JournalBlock
            imported.blockID = block.id
            imported.blockKind = JournalBlockKind(rawValue: block.kind)
            imported.blockCreatedAt = block.createdAt
            imported.blockUpdatedAt = block.updatedAt
            imported.blockSortOrder = block.sortOrder
            imported.textValue = block.text ?? ""
            imported.moodValue = block.mood ?? ""
            imported.durationValue = block.duration
            imported.sourceCaptureIDValue = block.sourceCaptureID
            imported.audioAttachmentIDValue = block.audioAttachmentID
            imported.photoAttachmentIDValue = block.photoAttachmentID
            imported.diaryEntry = entry
        }
    }

    private func formattedDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
    
    private func formattedFullDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func moodToEmoji(_ mood: String) -> String {
        switch mood.lowercased() {
        case "happy": return "☀️"
        case "calm": return "🍃"
        case "grateful": return "💗"
        case "excited": return "⭐"
        case "tired": return "🌙"
        case "anxious": return "💨"
        case "sad": return "🌧️"
        case "angry": return "🔥"
        default: return "📝"
        }
    }
}

// MARK: - Export Format Enum

enum ExportFormat: String, CaseIterable, Identifiable {
    case json = "JSON Backup"
    case text = "Plain Text"
    case markdown = "Markdown"
    case csv = "CSV Spreadsheet"
    case pdf = "PDF Document"
    case encryptedBackup = "Encrypted Backup"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .json: return "doc.badge.gearshape"
        case .text: return "doc.text"
        case .markdown: return "text.badge.checkmark"
        case .csv: return "tablecells"
        case .pdf: return "doc.richtext"
        case .encryptedBackup: return "lock.shield.fill"
        }
    }

    var fileExtension: String {
        switch self {
        case .json: return "json"
        case .text: return "txt"
        case .markdown: return "md"
        case .csv: return "csv"
        case .pdf: return "pdf"
        case .encryptedBackup: return "dvx"
        }
    }

    var description: String {
        switch self {
        case .json: return "Full backup with all data. Can be imported back."
        case .text: return "Simple readable format for archiving."
        case .markdown: return "Formatted text for notes apps."
        case .csv: return "Spreadsheet format for analysis."
        case .pdf: return "Beautiful formatted document."
        case .encryptedBackup: return "Password-protected backup. Maximum privacy."
        }
    }
}
