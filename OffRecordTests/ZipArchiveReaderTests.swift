import Foundation
import Testing
@testable import OffRecord

struct ZipArchiveReaderTests {

    private let text = Data(String(repeating: "Walked to the lake with Maya. ", count: 40).utf8)

    @Test func readsStoredAndDeflatedEntries() throws {
        let data = ImportTestFixtures.zip([
            .init(path: "Journal.json", data: text, deflate: true),
            .init(path: "photos/abc.png", data: ImportTestFixtures.pngData, deflate: false),
            .init(path: "empty.txt", data: Data(), deflate: true)
        ], comment: "made in a test")

        let archive = try ZipArchive(data: data)

        #expect(archive.filePaths == ["Journal.json", "photos/abc.png", "empty.txt"])
        #expect(try archive.contents(at: "Journal.json") == text)
        #expect(try archive.contents(at: "photos/abc.png") == ImportTestFixtures.pngData)
        #expect(try archive.contents(at: "empty.txt").isEmpty)
        #expect(archive.entry(at: "Journal.json")?.method == 8)
    }

    @Test func readsAnArchiveTheSystemMade() throws {
        let folder = try ImportTestFixtures.temporaryDirectory()
        try ImportTestFixtures.write([
            "Export/Entries/2025-03-04.html": text,
            "Export/Resources/IMG1.png": ImportTestFixtures.pngData
        ], under: folder)

        let archive = try ZipArchive(data: try ImportTestFixtures.systemZip(of: folder.appendingPathComponent("Export")))
        let paths = archive.filePaths

        let html = try #require(paths.first { $0.hasSuffix("Entries/2025-03-04.html") })
        let image = try #require(paths.first { $0.hasSuffix("Resources/IMG1.png") })
        #expect(try archive.contents(at: html) == text)
        #expect(try archive.contents(at: image) == ImportTestFixtures.pngData)
    }

    @Test func rejectsFilesThatAreNotZips() {
        #expect(throws: ZipArchive.ZipError.notAZip) {
            try ZipArchive(data: Data("not a zip at all, just some text in a file".utf8))
        }
        #expect(throws: ZipArchive.ZipError.notAZip) {
            try ZipArchive(data: Data([0x50, 0x4b]))
        }
    }

    @Test func reportsTruncatedArchives() {
        let data = ImportTestFixtures.zip([.init(path: "a.txt", data: text)])
        let cut = data.prefix(data.count / 2)

        #expect(throws: ZipArchive.ZipError.truncated) {
            try ZipArchive(data: Data(cut))
        }
    }

    @Test func detectsCorruptedContent() throws {
        var data = ImportTestFixtures.zip([.init(path: "a.txt", data: text, deflate: false)])
        // Flip a byte inside the stored payload (after the 30-byte header and 5-byte name).
        data[30 + 5 + 10] ^= 0xFF
        let archive = try ZipArchive(data: data)

        #expect(throws: ZipArchive.ZipError.checksumMismatch("a.txt")) {
            try archive.contents(at: "a.txt")
        }
    }

    @Test func detectsGarbageDeflateStreams() throws {
        var data = ImportTestFixtures.zip([.init(path: "a.txt", data: text, deflate: true)])
        for offset in (30 + 5)..<(30 + 5 + 12) {
            data[offset] = 0xFF
        }
        let archive = try ZipArchive(data: data)

        #expect(throws: (any Error).self) {
            try archive.contents(at: "a.txt")
        }
    }

    @Test func missingEntriesThrow() throws {
        let archive = try ZipArchive(data: ImportTestFixtures.zip([.init(path: "a.txt", data: text)]))
        #expect(throws: ZipArchive.ZipError.missingEntry("b.txt")) {
            try archive.contents(at: "b.txt")
        }
    }

    @Test func crc32MatchesTheKnownCheckValue() {
        #expect(ZipCRC32.checksum(Data("123456789".utf8)) == 0xCBF4_3926)
    }
}
