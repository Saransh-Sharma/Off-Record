//
//  EntryDetailView+Photos.swift
//  OffRecord
//
//  Loading the entry's photos and thumbnails, dropping thumbnails in the
//  background, and importing photos picked with Add Photos as photo blocks.
//

import SwiftUI
import CoreData
import PhotosUI

extension EntryDetailView {
    func loadPhotos() {
        if PhotoStorageManager.shared.migrateLegacyPhotos(for: entry, in: viewContext) {
            try? viewContext.save()
        }
        photoAttachments = PhotoStorageManager.shared.attachments(for: entry)
        photoAttachmentByID = Dictionary(uniqueKeysWithValues: photoAttachments.compactMap { attachment in
            guard let id = attachment.id else { return nil }
            return (id, attachment)
        })
        #if canImport(UIKit)
        photoImages = PhotoStorageManager.shared.thumbnailImages(for: entry)
        var thumbnails: [UUID: UIImage] = [:]
        for attachment in photoAttachments {
            guard let id = attachment.id,
                  let image = PhotoStorageManager.shared.thumbnailImage(for: attachment, maxPixelDimension: 720) else { continue }
            thumbnails[id] = image
        }
        photoThumbnailByID = thumbnails
        #endif
    }

    func clearPhotoThumbnails() {
        #if canImport(UIKit)
        photoImages = []
        photoThumbnailByID = [:]
        #endif
    }

    func handlePhotoSelection(_ items: [PhotosPickerItem]) {
        #if canImport(UIKit)
        let entryObjectID = entry.objectID
        for item in items {
            let token = PerformanceSignposts.begin("PhotoImport")
            item.loadTransferable(type: Data.self) { result in
                guard case .success(let data) = result, let data else {
                    PerformanceSignposts.end(token)
                    return
                }

                Task { @MainActor in
                    guard let jpegData = await PhotoAttachmentProcessor.shared.preparedJPEGData(from: data),
                          let image = PhotoStorageManager.thumbnailImage(from: jpegData) else {
                        PerformanceSignposts.end(token)
                        return
                    }

                    guard let entry = try? viewContext.existingObject(with: entryObjectID) as? DiaryEntry else {
                        PerformanceSignposts.end(token)
                        return
                    }

                    if let attachment = PhotoStorageManager.shared.addPhotoData(jpegData, to: entry, in: viewContext) {
                        JournalBlockTimelineStore.appendPhotoBlock(
                            attachment: attachment,
                            createdAt: entryTimestampNow(),
                            to: entry,
                            in: viewContext
                        )
                        photoAttachments.append(attachment)
                        photoImages.append(image)
                        savePhotos()
                    }
                    PerformanceSignposts.end(token)
                }
            }
        }
        selectedPhotos = []
        #endif
    }

    private func savePhotos() {
        entry.updatedAt = Date()
        try? viewContext.save()
        photoAttachments = PhotoStorageManager.shared.attachments(for: entry)
        loadBlocks(backfill: false)
        JournalSpotlightIndexer.shared.upsert(entry: entry)
    }

    private func photoAttachment(for block: NSManagedObject) -> PhotoAttachment? {
        guard let id = block.value(forKey: "photoAttachmentID") as? UUID else { return nil }
        return PhotoStorageManager.shared.attachments(for: entry).first { $0.id == id }
    }
}
