//
//  JournalImportService.swift
//  OffRecord
//
//  Turns another app's export into OffRecord entries. Parsing runs off the
//  main actor; the preview counts what's new against what's already here, and
//  the commit writes through the daily store so each day stays one entry:
//  imported entries become that day's text blocks in time order, with photos
//  up to the per-entry limit. Each new block carries a stable import key, so
//  importing the same file again adds nothing.
//

import CoreData
import Foundation
import os.log

private let importLogger = Logger(subsystem: "com.singularity.offrecord", category: "JournalImport")

struct JournalImportPreview: Identifiable, Sendable {
    let id = UUID()
    let format: JournalImportFormat
    let source: any JournalImportSource
    /// Entries that would be added, oldest first.
    let newDrafts: [ImportedEntryDraft]
    /// Entries already imported before (same minute and text).
    let duplicateCount: Int
    let skipped: [ImportSkippedItem]

    var photoCount: Int { newDrafts.reduce(0) { $0 + $1.photoPaths.count } }

    var dayCount: Int {
        Set(newDrafts.map { Calendar.current.startOfDay(for: $0.date) }).count
    }

    var dateRange: ClosedRange<Date>? {
        guard let first = newDrafts.first?.date, let last = newDrafts.last?.date else { return nil }
        return first...last
    }
}

struct JournalImportSummary: Equatable, Sendable {
    var entriesAdded = 0
    var daysTouched = 0
    var newDays = 0
    var photosAdded = 0
    /// Photos left out because the day already had the maximum.
    var photosOverLimit = 0
    var photosUnreadable = 0
    var duplicatesSkipped = 0
    var itemsSkipped = 0
}

@MainActor
enum JournalImportService {
    /// The same limit the photo pickers use, applied to the whole day's entry.
    static let maximumPhotosPerEntry = 5
    /// Entries saved per batch, so a long import doesn't hold everything in one save.
    static let batchSize = 100

    /// Reads `source` as `format`. Safe to call from any thread.
    nonisolated static func parse(
        _ source: any JournalImportSource,
        as format: JournalImportFormat,
        calendar: Calendar = .current
    ) throws -> JournalImportParseResult {
        switch format {
        case .dayOne: return try DayOneImporter.parse(source, calendar: calendar)
        case .appleJournal: return try AppleJournalImporter.parse(source, calendar: calendar)
        case .markdown: return try PlainTextJournalImporter.parse(source, calendar: calendar)
        case .csv: return try CSVJournalImporter.parse(source, calendar: calendar)
        }
    }

    /// Splits parsed drafts into new ones and ones already imported (by import key), oldest first.
    static func makePreview(
        format: JournalImportFormat,
        source: any JournalImportSource,
        parsed: JournalImportParseResult,
        context: NSManagedObjectContext
    ) -> JournalImportPreview {
        let sorted = parsed.drafts.sorted { lhs, rhs in
            lhs.date == rhs.date ? lhs.origin < rhs.origin : lhs.date < rhs.date
        }
        let existing = existingImportKeys(Set(sorted.map(\.importKey)), in: context)
        var seen = Set<UUID>()
        var fresh: [ImportedEntryDraft] = []
        var duplicates = 0
        for draft in sorted {
            let key = draft.importKey
            if existing.contains(key) || seen.contains(key) {
                duplicates += 1
            } else {
                seen.insert(key)
                fresh.append(draft)
            }
        }
        return JournalImportPreview(
            format: format,
            source: source,
            newDrafts: fresh,
            duplicateCount: duplicates,
            skipped: parsed.skipped
        )
    }

    /// Saves the preview's new entries. Reports progress from 0 to 1.
    static func commit(
        _ preview: JournalImportPreview,
        context: NSManagedObjectContext,
        progress: ((Double) -> Void)? = nil
    ) async throws -> JournalImportSummary {
        var summary = JournalImportSummary(duplicatesSkipped: preview.duplicateCount, itemsSkipped: preview.skipped.count)
        let drafts = preview.newDrafts
        guard !drafts.isEmpty else { return summary }

        // Keys can't have appeared since the preview unless the same file was imported twice at once.
        let alreadyImported = existingImportKeys(Set(drafts.map(\.importKey)), in: context)
        var touched: [NSManagedObjectID: DiaryEntry] = [:]
        var newDayIDs = Set<NSManagedObjectID>()

        for (index, draft) in drafts.enumerated() {
            let key = draft.importKey
            guard !alreadyImported.contains(key) else {
                summary.duplicatesSkipped += 1
                continue
            }

            let existedBefore = !(try DiaryEntryDailyStore.entries(on: draft.date, in: context)).isEmpty
            let entry = try DiaryEntryDailyStore.getOrCreateEntry(on: draft.date, in: context)
            if !existedBefore { newDayIDs.insert(entry.objectID) }

            var keyBlock = JournalBlockTimelineStore.appendTextBlock(
                text: draft.text,
                createdAt: draft.date,
                to: entry,
                in: context,
                sourceCaptureID: key
            )
            if let mood = draft.mood, mood != .none {
                JournalBlockTimelineStore.appendMoodBlock(mood: mood, createdAt: draft.date, to: entry, in: context)
            }
            if draft.isStarred {
                entry.isStarred = true
            }
            ImportedTagMapper.apply(draft.tags, to: entry, in: context)

            for path in draft.photoPaths {
                guard PhotoStorageManager.shared.attachments(for: entry).count < maximumPhotosPerEntry else {
                    summary.photosOverLimit += 1
                    continue
                }
                guard let jpeg = await preparedPhoto(at: path, in: preview.source),
                      let attachment = PhotoStorageManager.shared.addPhotoData(jpeg, to: entry, in: context) else {
                    summary.photosUnreadable += 1
                    continue
                }
                attachment.createdAt = draft.date
                let photoBlock = JournalBlockTimelineStore.appendPhotoBlock(attachment: attachment, createdAt: draft.date, to: entry, in: context)
                if keyBlock == nil {
                    // A photo-only entry: the first photo block carries the import key.
                    photoBlock?.sourceCaptureIDValue = key
                    keyBlock = photoBlock
                }
                summary.photosAdded += 1
            }

            summary.entriesAdded += 1
            touched[entry.objectID] = entry

            if (index + 1) % batchSize == 0 {
                try context.save()
                progress?(Double(index + 1) / Double(drafts.count))
                await Task.yield()
            }
        }

        if context.hasChanges {
            try context.save()
        }
        progress?(1)

        summary.daysTouched = touched.count
        summary.newDays = newDayIDs.count
        for entry in touched.values where !entry.isDeleted {
            // FridayProfileRebuilder observes the save; the search index and Spotlight are updated here,
            // as the other import paths do.
            EntryLearningPipeline.upsertSemanticEntry(entry)
            JournalSpotlightIndexer.shared.upsert(entry: entry)
        }
        importLogger.info("Imported \(summary.entriesAdded, privacy: .public) entries from \(preview.format.rawValue, privacy: .public)")
        return summary
    }

    /// Import keys already stored on blocks.
    static func existingImportKeys(_ keys: Set<UUID>, in context: NSManagedObjectContext) -> Set<UUID> {
        guard !keys.isEmpty else { return [] }
        var found = Set<UUID>()
        let all = Array(keys)
        for start in stride(from: 0, to: all.count, by: 500) {
            let chunk = Array(all[start..<min(start + 500, all.count)])
            let request = NSFetchRequest<NSDictionary>(entityName: "JournalBlock")
            request.predicate = NSPredicate(format: "sourceCaptureID IN %@", chunk)
            request.resultType = .dictionaryResultType
            request.propertiesToFetch = ["sourceCaptureID"]
            let rows = (try? context.fetch(request)) ?? []
            for row in rows {
                if let id = row["sourceCaptureID"] as? UUID { found.insert(id) }
            }
        }
        // Blocks inserted but not saved yet aren't visible to a dictionary fetch.
        for object in context.insertedObjects {
            if let block = object as? JournalBlock, let id = block.sourceCaptureIDValue, keys.contains(id) {
                found.insert(id)
            }
        }
        return found
    }

    /// Reads a photo from the source and re-encodes it as JPEG off the main actor (HEIC and PNG included).
    private static func preparedPhoto(at path: String, in source: any JournalImportSource) async -> Data? {
        let data = await Task.detached(priority: .userInitiated) { try? source.data(at: path) }.value
        guard let data, !data.isEmpty else { return nil }
        #if canImport(UIKit)
        return await PhotoAttachmentProcessor.shared.preparedJPEGData(from: data)
        #else
        return data
        #endif
    }
}
