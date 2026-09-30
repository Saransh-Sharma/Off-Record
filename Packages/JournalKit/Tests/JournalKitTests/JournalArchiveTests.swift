import CryptoKit
import Foundation
import Testing
@testable import JournalFoundation
@testable import JournalSecurityKit
@testable import ReflectionKit

struct JournalArchiveTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func encryptedRoundTripPreservesManifestAndPrivateContent() throws {
        let fixture = makeContent(includeMedia: true)
        let encrypted = try JournalArchiveCodec.seal(
            fixture,
            password: "correct horse battery staple",
            createdAt: now,
            timezone: TimeZone(identifier: "Asia/Kolkata")!
        )

        #expect(!String(decoding: encrypted, as: UTF8.self).contains("A private journal sentence"))
        let opened = try JournalArchiveCodec.open(encrypted, password: "correct horse battery staple")
        #expect(opened.content == fixture)
        #expect(opened.manifest.schemaVersion == 1)
        #expect(opened.manifest.timezoneIdentifier == "Asia/Kolkata")
        #expect(opened.manifest.entryCount == 1)
        #expect(opened.manifest.attachmentCount == 1)
        #expect(opened.manifest.mediaPayloadCount == 1)
        #expect(Array(encrypted.prefix(4)) == Array("DVX2".utf8))

        let encodedIterations = encrypted[4..<8].reduce(UInt32.zero) { partial, byte in
            (partial << 8) | UInt32(byte)
        }
        #expect(encodedIterations == 100_000)
    }

    @Test func legacyDVX1ArchiveStillDecryptsAfterKDFUpgrade() throws {
        let plaintext = Data("legacy private journal".utf8)
        let password = "legacy-password"
        let salt = Data(repeating: 0x5a, count: 32)
        let legacyKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: Data(password.utf8)),
            salt: salt,
            outputByteCount: 32
        )
        let sealed = try AES.GCM.seal(plaintext, using: legacyKey)
        var legacyArchive = Data("DVX1".utf8)
        legacyArchive.append(salt)
        legacyArchive.append(try #require(sealed.combined))

        #expect(try EncryptionService.decrypt(data: legacyArchive, password: password) == plaintext)
    }

    @Test func wrongPasswordAndCorruptionFailClosed() throws {
        let encrypted = try JournalArchiveCodec.seal(makeContent(includeMedia: true), password: "right")
        #expect(throws: EncryptionService.EncryptionError.self) {
            _ = try JournalArchiveCodec.open(encrypted, password: "wrong")
        }

        var corrupted = encrypted
        corrupted[corrupted.index(before: corrupted.endIndex)] ^= 0xff
        #expect(throws: EncryptionService.EncryptionError.self) {
            _ = try JournalArchiveCodec.open(corrupted, password: "right")
        }
    }

    @Test func restorePreviewIsDuplicateSafeAndReportsMissingMedia() throws {
        let content = makeContent(includeMedia: false)
        let encrypted = try JournalArchiveCodec.seal(content, password: "secret")
        let envelope = try JournalArchiveCodec.open(encrypted, password: "secret")
        let entry = content.entries[0]

        let keepExisting = JournalArchiveCodec.preview(
            envelope,
            existingEntries: [entry.id: entry.updatedAt.addingTimeInterval(60)],
            conflictPolicy: .keepNewest
        )
        #expect(keepExisting.entriesToSkip == 1)
        #expect(keepExisting.entriesToReplace == 0)
        #expect(keepExisting.missingAttachmentIDs == [content.attachments[0].id])

        let replace = JournalArchiveCodec.preview(
            envelope,
            existingEntries: [entry.id: entry.updatedAt.addingTimeInterval(-60)],
            conflictPolicy: .keepNewest
        )
        #expect(replace.entriesToReplace == 1)
        #expect(replace.entriesToSkip == 0)
    }

    private func makeContent(includeMedia: Bool) -> JournalArchiveContent {
        let entryID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let attachmentID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let entry = JournalSnapshot(
            id: entryID,
            date: now,
            createdAt: now,
            updatedAt: now,
            moodToken: "calm",
            blocks: [
                JournalBlockSnapshot(
                    id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                    kind: .text,
                    text: "A private journal sentence",
                    sortOrder: 0,
                    createdAt: now
                ),
                JournalBlockSnapshot(
                    id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
                    kind: .audio,
                    attachmentID: attachmentID,
                    sortOrder: 1,
                    createdAt: now
                )
            ]
        )
        let attachment = JournalAttachmentSnapshot(
            id: attachmentID,
            entryID: entryID,
            kind: .audio,
            availability: .locallyAvailable,
            fileName: "voice.m4a",
            mimeType: "audio/mp4",
            byteCount: 4,
            createdAt: now,
            updatedAt: now,
            duration: 1
        )
        let insight = SavedInsight(
            id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
            source: .assistant,
            sourceID: "eva-1",
            title: "A useful pattern",
            summary: "Quiet mornings help.",
            savedAt: now,
            updatedAt: now
        )
        return JournalArchiveContent(
            entries: [entry],
            attachments: [attachment],
            savedInsights: [insight],
            mediaPayloads: includeMedia ? [attachmentID: Data([1, 2, 3, 4])] : [:]
        )
    }
}
