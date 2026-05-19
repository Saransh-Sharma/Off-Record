//
//  PhotoStorageManager.swift
//  OffRecord
//
//  Manages synced photo attachments for diary entries.
//  Legacy local files in Application Support/Photos are migrated into Core Data.
//

import Foundation
import CoreData
#if canImport(UIKit)
import ImageIO
import UIKit
#endif

final class PhotoStorageManager {
    static let shared = PhotoStorageManager()

    private let photosDirectoryName = "Photos"

    private var photosDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent(photosDirectoryName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private init() {}

    // MARK: - Synced Attachments

    #if canImport(UIKit)
    @discardableResult
    func addPhoto(_ image: UIImage, to entry: DiaryEntry, in context: NSManagedObjectContext) -> PhotoAttachment? {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return nil }
        return addPhotoData(data, to: entry, in: context)
    }
    #endif

    @discardableResult
    func addPhotoData(_ data: Data, to entry: DiaryEntry, in context: NSManagedObjectContext) -> PhotoAttachment? {
        let attachment = PhotoAttachment(context: context)
        attachment.id = UUID()
        attachment.createdAt = Date()
        attachment.imageData = data
        attachment.mimeType = "image/jpeg"
        attachment.fileName = "\(attachment.id?.uuidString ?? UUID().uuidString).jpg"
        attachment.sortOrder = Int32(attachments(for: entry).count)
        attachment.entry = entry
        entry.updatedAt = Date()
        return attachment
    }

    func attachments(for entry: DiaryEntry) -> [PhotoAttachment] {
        let photoSet = entry.value(forKey: "photos") as? Set<PhotoAttachment> ?? []
        return photoSet.sorted {
            if $0.sortOrder == $1.sortOrder {
                return ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast)
            }
            return $0.sortOrder < $1.sortOrder
        }
    }

    #if canImport(UIKit)
    func images(for entry: DiaryEntry) -> [UIImage] {
        attachments(for: entry).compactMap { attachment in
            guard let data = attachment.imageData else { return nil }
            return UIImage(data: data)
        }
    }

    func thumbnailImage(for attachment: PhotoAttachment, maxPixelDimension: CGFloat = 240) -> UIImage? {
        guard let data = attachment.imageData else { return nil }
        return Self.thumbnailImage(from: data, maxPixelDimension: maxPixelDimension)
    }

    func thumbnailImages(for entry: DiaryEntry, maxPixelDimension: CGFloat = 240) -> [UIImage] {
        attachments(for: entry).compactMap {
            thumbnailImage(for: $0, maxPixelDimension: maxPixelDimension)
        }
    }

    static func thumbnailImage(from data: Data, maxPixelDimension: CGFloat = 240) -> UIImage? {
        autoreleasepool {
            let sourceOptions = [
                kCGImageSourceShouldCache: false
            ] as CFDictionary
            guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
                return nil
            }

            let thumbnailOptions = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelDimension
            ] as CFDictionary
            guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
                return nil
            }
            return UIImage(cgImage: thumbnail)
        }
    }
    #endif

    func removePhoto(_ attachment: PhotoAttachment, from entry: DiaryEntry, in context: NSManagedObjectContext) {
        context.delete(attachment)
        entry.updatedAt = Date()

        for (index, remaining) in attachments(for: entry).enumerated() where !remaining.isDeleted {
            remaining.sortOrder = Int32(index)
        }
    }

    func migrateLegacyPhotos(in context: NSManagedObjectContext) {
        context.perform {
            let request: NSFetchRequest<DiaryEntry> = DiaryEntry.fetchRequest()
            request.predicate = NSPredicate(format: "photoFileNames != nil AND photoFileNames != ''")

            do {
                let entries = try context.fetch(request)
                var didMigrate = false

                for entry in entries {
                    if self.migrateLegacyPhotos(for: entry, in: context) {
                        didMigrate = true
                    }
                }

                if didMigrate && context.hasChanges {
                    try context.save()
                }
            } catch {
                #if DEBUG
                print("Failed to migrate legacy photos: \(error)")
                #endif
            }
        }
    }

    @discardableResult
    func migrateLegacyPhotos(for entry: DiaryEntry, in context: NSManagedObjectContext) -> Bool {
        guard attachments(for: entry).isEmpty else { return false }

        let fileNames = Self.parsePhotoFileNames(entry.value(forKey: "photoFileNames") as? String)
        guard !fileNames.isEmpty else { return false }

        var didMigrate = false
        for fileName in fileNames {
            let fileURL = photosDirectory.appendingPathComponent(fileName)
            guard let data = try? Data(contentsOf: fileURL) else { continue }
            let attachment = addPhotoData(data, to: entry, in: context)
            attachment?.fileName = fileName
            didMigrate = didMigrate || attachment != nil
        }

        entry.setValue(nil, forKey: "photoFileNames")
        return didMigrate
    }

    // MARK: - Legacy Filename Helpers

    static func parsePhotoFileNames(_ jsonString: String?) -> [String] {
        guard let jsonString, !jsonString.isEmpty,
              let data = jsonString.data(using: .utf8),
              let array = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return array
    }

    static func encodePhotoFileNames(_ fileNames: [String]) -> String {
        guard !fileNames.isEmpty,
              let data = try? JSONEncoder().encode(fileNames),
              let jsonString = String(data: data, encoding: .utf8) else {
            return ""
        }
        return jsonString
    }
}
