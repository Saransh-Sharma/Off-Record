import Compression
import Foundation
@testable import OffRecord

/// Builds ZIP archives and export folders in test code, so importer tests need no checked-in fixtures.
enum ImportTestFixtures {
    struct ZipFile {
        var path: String
        var data: Data
        var deflate: Bool = true
    }

    /// A minimal ZIP writer: stored or deflated entries, a central directory, and an end record.
    static func zip(_ files: [ZipFile], comment: String = "") -> Data {
        var archive = Data()
        var central = Data()
        for file in files {
            let name = Data(file.path.utf8)
            let crc = ZipCRC32.checksum(file.data)
            let payload = file.deflate ? deflated(file.data) : file.data
            let method: UInt16 = file.deflate ? 8 : 0
            let offset = UInt32(archive.count)

            archive.append(le32(0x0403_4b50))
            archive.append(le16(20))
            archive.append(le16(0x0800))          // UTF-8 names
            archive.append(le16(method))
            archive.append(le16(0)); archive.append(le16(0x5821)) // time, date
            archive.append(le32(crc))
            archive.append(le32(UInt32(payload.count)))
            archive.append(le32(UInt32(file.data.count)))
            archive.append(le16(UInt16(name.count)))
            archive.append(le16(0))
            archive.append(name)
            archive.append(payload)

            central.append(le32(0x0201_4b50))
            central.append(le16(20)); central.append(le16(20))
            central.append(le16(0x0800))
            central.append(le16(method))
            central.append(le16(0)); central.append(le16(0x5821))
            central.append(le32(crc))
            central.append(le32(UInt32(payload.count)))
            central.append(le32(UInt32(file.data.count)))
            central.append(le16(UInt16(name.count)))
            central.append(le16(0)); central.append(le16(0)); central.append(le16(0)); central.append(le16(0))
            central.append(le32(0))
            central.append(le32(offset))
            central.append(name)
        }
        let centralOffset = UInt32(archive.count)
        archive.append(central)
        let commentData = Data(comment.utf8)
        archive.append(le32(0x0605_4b50))
        archive.append(le16(0)); archive.append(le16(0))
        archive.append(le16(UInt16(files.count))); archive.append(le16(UInt16(files.count)))
        archive.append(le32(UInt32(central.count)))
        archive.append(le32(centralOffset))
        archive.append(le16(UInt16(commentData.count)))
        archive.append(commentData)
        return archive
    }

    static func deflated(_ data: Data) -> Data {
        guard !data.isEmpty else { return Data() }
        let capacity = data.count + 1_024
        var buffer = [UInt8](repeating: 0, count: capacity)
        let written = data.withUnsafeBytes { source -> Int in
            compression_encode_buffer(&buffer, capacity, source.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB)
        }
        return Data(buffer[0..<written])
    }

    /// A fresh temporary folder for one test.
    static func temporaryDirectory(_ name: String = UUID().uuidString) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("OffRecordImportTests", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Writes `files` (relative path → contents) under `root`.
    static func write(_ files: [String: Data], under root: URL) throws {
        for (path, data) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
    }

    /// A real archive made by the system: NSFileCoordinator zips a folder for uploading.
    static func systemZip(of folder: URL) throws -> Data {
        var coordinationError: NSError?
        var result: Result<Data, Error> = .failure(CocoaError(.fileReadUnknown))
        NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading, error: &coordinationError) { zipURL in
            result = Result { try Data(contentsOf: zipURL) }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }

    /// A tiny valid PNG (1×1, opaque).
    static let pngData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC")!

    private static func le16(_ value: UInt16) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
    private static func le32(_ value: UInt32) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
}
