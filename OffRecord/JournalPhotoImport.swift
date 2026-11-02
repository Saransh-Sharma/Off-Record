//
//  JournalPhotoImport.swift
//  OffRecord
//
//  Adds photos that arrive from outside the photo picker (a Journaling
//  Suggestion, the Create Entry App Intent) to an entry the same way the
//  picker does: JPEG preparation off the main actor, a synced attachment,
//  and a photo block on the entry's timeline. One import adds at most
//  `PhotoStorageManager.maximumPhotosPerImport` photos.
//

import CoreData
import Foundation
import UniformTypeIdentifiers

@MainActor
enum JournalPhotoImport {
    /// The items one import may add, in their original order.
    nonisolated static func capped<Item>(_ items: [Item], limit: Int = PhotoStorageManager.maximumPhotosPerImport) -> [Item] {
        Array(items.prefix(max(0, limit)))
    }

    /// Whether a file of `type` should be imported as a photo. Unknown types are tried,
    /// since image decoding rejects anything that isn't an image.
    nonisolated static func isImportablePhoto(type: UTType?) -> Bool {
        guard let type else { return true }
        return type.conforms(to: .image)
    }

    /// Attaches up to the import limit of `imageData` to `entry` and saves.
    /// Returns how many photos were saved.
    @discardableResult
    static func attach(
        _ imageData: [Data],
        to entry: DiaryEntry,
        capturedAt: Date,
        in context: NSManagedObjectContext
    ) async -> Int {
        var imported = 0
        for data in capped(imageData) {
            guard let jpegData = await PhotoAttachmentProcessor.shared.preparedJPEGData(from: data),
                  let attachment = PhotoStorageManager.shared.addPhotoData(jpegData, to: entry, in: context) else {
                continue
            }
            JournalBlockTimelineStore.appendPhotoBlock(attachment: attachment, createdAt: capturedAt, to: entry, in: context)
            imported += 1
        }
        guard imported > 0 else { return 0 }

        entry.updatedAt = Date()
        do {
            try context.save()
        } catch {
            context.rollback()
            return 0
        }
        JournalSpotlightIndexer.shared.upsert(entry: entry)
        return imported
    }
}
