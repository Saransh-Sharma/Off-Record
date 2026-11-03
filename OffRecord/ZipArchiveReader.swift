//
//  ZipArchiveReader.swift
//  OffRecord
//
//  A small read-only ZIP reader for importing other apps' exports. iOS has no
//  public unzip API (NSFileCoordinator only creates archives), so this parses
//  the central directory itself and inflates entries with Compression.
//  Supports stored and deflated entries and ZIP64 sizes. Nothing is written to
//  disk by path: entries are read into memory by name, so a hostile archive
//  can't place files outside a folder.
//

import Compression
import Foundation

struct ZipArchive: Sendable {
    struct Entry: Hashable, Sendable {
        let path: String
        let method: UInt16
        let flags: UInt16
        let crc32: UInt32
        let compressedSize: UInt64
        let uncompressedSize: UInt64
        let localHeaderOffset: UInt64

        var isDirectory: Bool { path.hasSuffix("/") }
        var isEncrypted: Bool { flags & 0x0001 != 0 }
    }

    enum ZipError: Error, Equatable {
        case notAZip
        case truncated
        case encrypted(String)
        case unsupportedMethod(UInt16)
        case corrupt(String)
        case checksumMismatch(String)
        case entryTooLarge(String)
        case missingEntry(String)
    }

    /// Entries larger than this are refused so one file can't exhaust memory.
    static let maximumEntrySize: UInt64 = 512 * 1024 * 1024

    let entries: [Entry]
    private let data: Data
    private let entriesByPath: [String: Entry]

    init(url: URL) throws {
        try self.init(data: Data(contentsOf: url, options: .mappedIfSafe))
    }

    init(data: Data) throws {
        self.data = data
        let entries = try Self.readCentralDirectory(in: data)
        self.entries = entries
        var byPath: [String: Entry] = [:]
        for entry in entries where byPath[entry.path] == nil {
            byPath[entry.path] = entry
        }
        self.entriesByPath = byPath
    }

    /// Paths of every file (not folder) in the archive.
    var filePaths: [String] {
        entries.filter { !$0.isDirectory }.map(\.path)
    }

    func entry(at path: String) -> Entry? {
        entriesByPath[path]
    }

    func contents(at path: String) throws -> Data {
        guard let entry = entry(at: path) else { throw ZipError.missingEntry(path) }
        return try contents(of: entry)
    }

    func contents(of entry: Entry) throws -> Data {
        guard !entry.isEncrypted else { throw ZipError.encrypted(entry.path) }
        guard entry.uncompressedSize <= Self.maximumEntrySize, entry.compressedSize <= Self.maximumEntrySize else {
            throw ZipError.entryTooLarge(entry.path)
        }

        let headerOffset = Int(entry.localHeaderOffset)
        guard data.count >= headerOffset + 30 else { throw ZipError.truncated }
        guard Self.uint32(data, headerOffset) == 0x0403_4b50 else { throw ZipError.corrupt(entry.path) }
        let nameLength = Int(Self.uint16(data, headerOffset + 26))
        let extraLength = Int(Self.uint16(data, headerOffset + 28))
        let start = headerOffset + 30 + nameLength + extraLength
        let end = start + Int(entry.compressedSize)
        guard start <= end, end <= data.count else { throw ZipError.truncated }
        let compressed = data.subdata(in: (data.startIndex + start)..<(data.startIndex + end))

        let output: Data
        switch entry.method {
        case 0:
            output = compressed
        case 8:
            output = try Self.inflate(compressed, expectedSize: Int(entry.uncompressedSize), path: entry.path)
        default:
            throw ZipError.unsupportedMethod(entry.method)
        }
        guard output.count == Int(entry.uncompressedSize) else { throw ZipError.corrupt(entry.path) }
        guard ZipCRC32.checksum(output) == entry.crc32 else { throw ZipError.checksumMismatch(entry.path) }
        return output
    }

    // MARK: - Central directory

    private static func readCentralDirectory(in data: Data) throws -> [Entry] {
        guard data.count >= 22 else { throw ZipError.notAZip }
        guard let eocd = findEndOfCentralDirectory(in: data) else {
            // A local header at the start without a directory means the file was cut short.
            throw data.count >= 4 && uint32(data, 0) == 0x0403_4b50 ? ZipError.truncated : ZipError.notAZip
        }

        var entryCount = UInt64(uint16(data, eocd + 10))
        var directorySize = UInt64(uint32(data, eocd + 12))
        var directoryOffset = UInt64(uint32(data, eocd + 16))

        if entryCount == 0xFFFF || directorySize == 0xFFFF_FFFF || directoryOffset == 0xFFFF_FFFF {
            let locator = eocd - 20
            guard locator >= 0, uint32(data, locator) == 0x0706_4b50 else { throw ZipError.corrupt("zip64 locator") }
            let recordOffset = Int(clamping: uint64(data, locator + 8))
            guard recordOffset >= 0, recordOffset + 56 <= data.count, uint32(data, recordOffset) == 0x0606_4b50 else {
                throw ZipError.corrupt("zip64 record")
            }
            entryCount = uint64(data, recordOffset + 32)
            directorySize = uint64(data, recordOffset + 40)
            directoryOffset = uint64(data, recordOffset + 48)
        }

        guard directoryOffset + directorySize <= UInt64(data.count) else { throw ZipError.truncated }
        var cursor = Int(directoryOffset)
        var entries: [Entry] = []
        entries.reserveCapacity(Int(min(entryCount, 100_000)))

        for _ in 0..<entryCount {
            guard cursor + 46 <= data.count else { throw ZipError.truncated }
            guard uint32(data, cursor) == 0x0201_4b50 else { throw ZipError.corrupt("central directory") }
            let flags = uint16(data, cursor + 8)
            let method = uint16(data, cursor + 10)
            let crc = uint32(data, cursor + 16)
            var compressedSize = UInt64(uint32(data, cursor + 20))
            var uncompressedSize = UInt64(uint32(data, cursor + 24))
            let nameLength = Int(uint16(data, cursor + 28))
            let extraLength = Int(uint16(data, cursor + 30))
            let commentLength = Int(uint16(data, cursor + 32))
            var localOffset = UInt64(uint32(data, cursor + 42))
            let nameStart = cursor + 46
            let extraStart = nameStart + nameLength
            let next = extraStart + extraLength + commentLength
            guard next <= data.count else { throw ZipError.truncated }

            let nameData = data.subdata(in: (data.startIndex + nameStart)..<(data.startIndex + extraStart))
            let name = String(data: nameData, encoding: .utf8) ?? String(data: nameData, encoding: .isoLatin1) ?? ""

            // ZIP64 extended information: only the fields saturated above are present, in this order.
            var extraCursor = extraStart
            let extraEnd = extraStart + extraLength
            while extraCursor + 4 <= extraEnd {
                let headerID = uint16(data, extraCursor)
                let size = Int(uint16(data, extraCursor + 2))
                var field = extraCursor + 4
                if headerID == 0x0001 {
                    if uncompressedSize == 0xFFFF_FFFF, field + 8 <= extraEnd {
                        uncompressedSize = uint64(data, field); field += 8
                    }
                    if compressedSize == 0xFFFF_FFFF, field + 8 <= extraEnd {
                        compressedSize = uint64(data, field); field += 8
                    }
                    if localOffset == 0xFFFF_FFFF, field + 8 <= extraEnd {
                        localOffset = uint64(data, field)
                    }
                }
                extraCursor += 4 + size
            }

            // Skip macOS resource forks and empty names; neither holds journal content.
            if !name.isEmpty, !name.hasPrefix("__MACOSX/") {
                entries.append(Entry(
                    path: name,
                    method: method,
                    flags: flags,
                    crc32: crc,
                    compressedSize: compressedSize,
                    uncompressedSize: uncompressedSize,
                    localHeaderOffset: localOffset
                ))
            }
            cursor = next
        }
        return entries
    }

    private static func findEndOfCentralDirectory(in data: Data) -> Int? {
        let lowest = max(0, data.count - 22 - 65_535)
        var offset = data.count - 22
        while offset >= lowest {
            if uint32(data, offset) == 0x0605_4b50 {
                let commentLength = Int(uint16(data, offset + 20))
                if offset + 22 + commentLength <= data.count { return offset }
            }
            offset -= 1
        }
        return nil
    }

    // MARK: - Inflate

    private static func inflate(_ compressed: Data, expectedSize: Int, path: String) throws -> Data {
        guard expectedSize > 0 else { return Data() }
        guard !compressed.isEmpty else { throw ZipError.corrupt(path) }
        // One byte more than expected, so an entry that inflates larger is caught.
        let capacity = expectedSize + 1
        var buffer = [UInt8](repeating: 0, count: capacity)
        let written = compressed.withUnsafeBytes { source -> Int in
            guard let base = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_decode_buffer(&buffer, capacity, base, compressed.count, nil, COMPRESSION_ZLIB)
        }
        guard written == expectedSize else { throw ZipError.corrupt(path) }
        return Data(buffer[0..<expectedSize])
    }

    // MARK: - Little-endian reads

    private static func uint16(_ data: Data, _ offset: Int) -> UInt16 {
        guard offset >= 0, offset + 2 <= data.count else { return 0 }
        let base = data.startIndex + offset
        return UInt16(data[base]) | UInt16(data[base + 1]) << 8
    }

    private static func uint32(_ data: Data, _ offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= data.count else { return 0 }
        let base = data.startIndex + offset
        return UInt32(data[base]) | UInt32(data[base + 1]) << 8 | UInt32(data[base + 2]) << 16 | UInt32(data[base + 3]) << 24
    }

    private static func uint64(_ data: Data, _ offset: Int) -> UInt64 {
        UInt64(uint32(data, offset)) | UInt64(uint32(data, offset + 4)) << 32
    }
}

/// CRC-32 (IEEE 802.3), as ZIP uses it.
enum ZipCRC32 {
    private static let table: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 {
            value = value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1
        }
        return value
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        data.withUnsafeBytes { bytes in
            for byte in bytes {
                crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
            }
        }
        return crc ^ 0xFFFF_FFFF
    }
}
