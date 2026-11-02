//
//  StoreFileCopier.swift
//  OffRecord
//
//  Copies the files that make up the journal store so someone can keep or
//  send them when the store won't open. It only reads the originals.
//

import Foundation

enum StoreFileCopier {
    /// The database, its write-ahead log, and Core Data's folder for large
    /// attributes (photo bytes live there, since PhotoAttachment.imageData
    /// allows external storage). Only the ones that exist.
    static func storeFileURLs(for storeURL: URL, fileManager: FileManager = .default) -> [URL] {
        let folder = storeURL.deletingLastPathComponent()
        let name = storeURL.lastPathComponent
        let modelName = storeURL.deletingPathExtension().lastPathComponent
        let candidates = [
            storeURL,
            folder.appendingPathComponent(name + "-wal"),
            folder.appendingPathComponent(name + "-shm"),
            folder.appendingPathComponent("." + modelName + "_SUPPORT", isDirectory: true),
        ]
        return candidates.filter { fileManager.fileExists(atPath: $0.path) }
    }

    /// Copies the store files into a new folder inside `parent` and returns it.
    @discardableResult
    static func copyStoreFiles(
        of storeURL: URL,
        into parent: URL,
        date: Date = Date(),
        fileManager: FileManager = .default
    ) throws -> URL {
        let sources = storeFileURLs(for: storeURL, fileManager: fileManager)
        guard !sources.isEmpty else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: storeURL.path])
        }
        let folder = parent.appendingPathComponent(folderName(for: date), isDirectory: true)
        if fileManager.fileExists(atPath: folder.path) {
            try fileManager.removeItem(at: folder)
        }
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        for source in sources {
            try fileManager.copyItem(at: source, to: folder.appendingPathComponent(source.lastPathComponent))
        }
        return folder
    }

    /// A copy of the store files as one .zip in the temporary folder, ready to share.
    /// Zipping uses NSFileCoordinator, so no third-party code is involved.
    static func makeShareableArchive(
        of storeURL: URL,
        date: Date = Date(),
        fileManager: FileManager = .default
    ) throws -> URL {
        let staging = fileManager.temporaryDirectory.appendingPathComponent("StoreCopy-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }
        let folder = try copyStoreFiles(of: storeURL, into: staging, date: date, fileManager: fileManager)

        let archive = fileManager.temporaryDirectory.appendingPathComponent(folder.lastPathComponent + ".zip")
        if fileManager.fileExists(atPath: archive.path) {
            try fileManager.removeItem(at: archive)
        }
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading, error: &coordinationError) { zipURL in
            do {
                try fileManager.copyItem(at: zipURL, to: archive)
            } catch {
                copyError = error
            }
        }
        if let error = coordinationError ?? copyError { throw error }
        return archive
    }

    static func folderName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        return "OffRecord Store Copy \(formatter.string(from: date))"
    }
}
