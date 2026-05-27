import CoreData
import Foundation
import Testing
@testable import OffRecord

@MainActor
struct WatchQuickCaptureTests {
    @Test func recentProjectionCapsAtTwentyWithoutDroppingOutbox() {
        let now = Date(timeIntervalSince1970: 1_000)
        let outbox = (0..<25).map { index in
            WatchRecentCapture(
                envelope: WatchCaptureEnvelope(kind: .speak, createdAtUTC: now.addingTimeInterval(Double(index)), text: "Item \(index)"),
                syncState: .queued,
                transferKind: .metadata,
                updatedAtUTC: now.addingTimeInterval(Double(index))
            )
        }

        let recent = WatchCaptureQueuePolicy.recentProjection(from: outbox)

        #expect(outbox.count == 25)
        #expect(recent.count == 20)
        #expect(recent.first?.envelope.text == "Item 24")
    }

    @Test func retryBackoffWaitsForDueTimeAndStaleSending() {
        let now = Date(timeIntervalSince1970: 2_000)
        let envelope = WatchCaptureEnvelope(kind: .speak, createdAtUTC: now, text: "Retry")
        let waiting = WatchRecentCapture(
            envelope: envelope,
            syncState: .failed,
            transferKind: .metadata,
            attemptCount: 2,
            nextAttemptAtUTC: now.addingTimeInterval(30),
            updatedAtUTC: now
        )
        let staleSending = WatchRecentCapture(
            envelope: envelope,
            syncState: .sending,
            transferKind: .metadata,
            attemptCount: 1,
            lastAttemptAtUTC: now.addingTimeInterval(-180),
            updatedAtUTC: now
        )
        let freshSending = WatchRecentCapture(
            envelope: envelope,
            syncState: .sending,
            transferKind: .metadata,
            attemptCount: 1,
            lastAttemptAtUTC: now.addingTimeInterval(-20),
            updatedAtUTC: now
        )

        #expect(!WatchCaptureQueuePolicy.shouldAttemptTransfer(waiting, now: now))
        #expect(WatchCaptureQueuePolicy.shouldAttemptTransfer(staleSending, now: now))
        #expect(!WatchCaptureQueuePolicy.shouldAttemptTransfer(freshSending, now: now))
        #expect(WatchCaptureQueuePolicy.backoffDelay(forAttempt: 1) == 15)
        #expect(WatchCaptureQueuePolicy.backoffDelay(forAttempt: 2) == 30)
    }

    @Test func duplicateWatchMoodImportCreatesOneReceiptAndOneEntry() throws {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        WatchCaptureImporter.shared.start(context: context)

        let captureID = UUID()
        let envelope = WatchCaptureEnvelope(
            captureID: captureID,
            kind: .mood,
            createdAtUTC: Date(timeIntervalSince1970: 1_800),
            moodValue: Mood.calm.rawValue,
            textPreview: "Calm"
        )

        let firstEntryID = try WatchCaptureImporter.shared.importForTesting(envelope)
        let secondEntryID = try WatchCaptureImporter.shared.importForTesting(envelope)

        #expect(firstEntryID == secondEntryID)

        let receipts = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "WatchImportReceipt"))
        #expect(receipts.count == 1)

        let entries = try context.fetch(DiaryEntry.fetchRequest())
        #expect(entries.count == 1)
        #expect(entries.first?.mood == Mood.calm.rawValue)
    }

    @Test func watchSpeakImportAppendsToDailyEntry() throws {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        WatchCaptureImporter.shared.start(context: context)

        let date = Date(timeIntervalSince1970: 3_600)
        let first = WatchCaptureEnvelope(kind: .speak, createdAtUTC: date, text: "First thought", textPreview: "First")
        let second = WatchCaptureEnvelope(kind: .speak, createdAtUTC: date, text: "Second thought", textPreview: "Second")

        try WatchCaptureImporter.shared.importForTesting(first)
        try WatchCaptureImporter.shared.importForTesting(second)

        let entries = try context.fetch(DiaryEntry.fetchRequest())
        #expect(entries.count == 1)
        #expect(entries.first?.text?.contains("First thought") == true)
        #expect(entries.first?.text?.contains("Second thought") == true)
    }

    @Test func watchAudioImportCreatesAttachmentAndLegacyReference() throws {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        WatchCaptureImporter.shared.start(context: context)

        let captureID = UUID()
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
        try Data([0, 1, 2, 3]).write(to: tempURL)
        let manifest = WatchAudioManifest(captureID: captureID, fileName: tempURL.lastPathComponent, duration: 4, byteCount: 4)
        let envelope = WatchCaptureEnvelope(
            captureID: captureID,
            kind: .audio,
            createdAtUTC: Date(timeIntervalSince1970: 7_200),
            speechTruthState: .audioOnly,
            audioManifest: manifest
        )

        try WatchCaptureImporter.shared.importForTesting(envelope, audioFileURL: tempURL)

        let entries = try context.fetch(DiaryEntry.fetchRequest())
        let entry = try #require(entries.first)
        #expect(entry.audioFileName?.hasPrefix("watch-\(captureID.uuidString)") == true)
        #expect(entry.duration == 4)

        let attachments = (entry.value(forKey: "audioAttachments") as? Set<NSManagedObject>) ?? []
        #expect(attachments.count == 1)
        #expect(attachments.first?.value(forKey: "sourceCaptureID") as? UUID == captureID)
        #expect(blocks(for: entry, kind: .audio).count == 1)
        #expect(blocks(for: entry, kind: .audio).first?.value(forKey: "sourceCaptureID") as? UUID == captureID)
    }

    @Test func twoWatchAudioCapturesSameDayCreateTwoAttachmentsAndBlocks() throws {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        WatchCaptureImporter.shared.start(context: context)

        let day = Date(timeIntervalSince1970: 11_000)
        let firstCaptureID = UUID()
        let secondCaptureID = UUID()
        let firstURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
        let secondURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
        try Data([0, 1, 2]).write(to: firstURL)
        try Data([3, 4, 5, 6]).write(to: secondURL)

        let firstManifest = WatchAudioManifest(captureID: firstCaptureID, fileName: firstURL.lastPathComponent, duration: 3, byteCount: 3, createdAtUTC: day)
        let secondManifest = WatchAudioManifest(captureID: secondCaptureID, fileName: secondURL.lastPathComponent, duration: 4, byteCount: 4, createdAtUTC: day.addingTimeInterval(90))
        let firstEnvelope = WatchCaptureEnvelope(captureID: firstCaptureID, kind: .audio, createdAtUTC: day, speechTruthState: .audioOnly, audioManifest: firstManifest)
        let secondEnvelope = WatchCaptureEnvelope(captureID: secondCaptureID, kind: .audio, createdAtUTC: day.addingTimeInterval(90), speechTruthState: .audioOnly, audioManifest: secondManifest)

        try WatchCaptureImporter.shared.importForTesting(firstEnvelope, audioFileURL: firstURL)
        try WatchCaptureImporter.shared.importForTesting(secondEnvelope, audioFileURL: secondURL)

        let entries = try context.fetch(DiaryEntry.fetchRequest())
        let entry = try #require(entries.first)
        #expect(entries.count == 1)
        #expect(AudioAttachmentStore.audioAttachments(for: entry).count == 2)
        #expect(blocks(for: entry, kind: .audio).count == 2)
        #expect(entry.duration == 7)
    }

    @Test func watchAudioMetadataWithoutFileDoesNotCreateReceiptOrEntry() throws {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        WatchCaptureImporter.shared.start(context: context)

        let captureID = UUID()
        let manifest = WatchAudioManifest(captureID: captureID, fileName: "missing.m4a", duration: 9, byteCount: 99)
        let envelope = WatchCaptureEnvelope(
            captureID: captureID,
            kind: .audio,
            createdAtUTC: Date(timeIntervalSince1970: 8_000),
            speechTruthState: .audioOnly,
            audioManifest: manifest
        )

        #expect(throws: Error.self) {
            try WatchCaptureImporter.shared.importForTesting(envelope)
        }

        let receipts = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "WatchImportReceipt"))
        let entries = try context.fetch(DiaryEntry.fetchRequest())
        #expect(receipts.isEmpty)
        #expect(entries.isEmpty)
    }

    @Test func duplicateWatchAudioDeliveryDoesNotCreateSecondAttachment() throws {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        WatchCaptureImporter.shared.start(context: context)

        let captureID = UUID()
        let firstURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
        let secondURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
        try Data([0, 1, 2]).write(to: firstURL)
        try Data([3, 4, 5]).write(to: secondURL)

        let manifest = WatchAudioManifest(captureID: captureID, fileName: firstURL.lastPathComponent, duration: 3, byteCount: 3)
        let envelope = WatchCaptureEnvelope(
            captureID: captureID,
            kind: .audio,
            createdAtUTC: Date(timeIntervalSince1970: 9_000),
            speechTruthState: .audioOnly,
            audioManifest: manifest
        )

        let metadata = try envelope.userInfoPayload()
        WatchCaptureImporter.shared.receiveFileForTesting(at: firstURL, metadata: metadata)
        WatchCaptureImporter.shared.receiveFileForTesting(at: secondURL, metadata: metadata)

        let entries = try context.fetch(DiaryEntry.fetchRequest())
        let entry = try #require(entries.first)
        let attachments = (entry.value(forKey: "audioAttachments") as? Set<NSManagedObject>) ?? []
        #expect(attachments.count == 1)
        #expect(blocks(for: entry, kind: .audio).count == 1)

        let receipts = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "WatchImportReceipt"))
        #expect(receipts.count == 1)
    }

    @Test func backupRoundTripPreservesMultipleAudioAttachments() throws {
        let sourceController = PersistenceController(inMemory: true)
        let sourceContext = sourceController.container.viewContext
        let entry = DiaryEntry(context: sourceContext)
        entry.id = UUID()
        entry.date = Date(timeIntervalSince1970: 10_000)
        entry.createdAt = entry.date
        entry.updatedAt = entry.date
        entry.text = "Voice day"
        let firstFileName = "backup-first-\(UUID().uuidString).m4a"
        let secondFileName = "backup-second-\(UUID().uuidString).m4a"
        let firstURL = try AudioAttachmentStore.destinationURL(for: firstFileName)
        let secondURL = try AudioAttachmentStore.destinationURL(for: secondFileName)
        try Data([1, 2, 3, 4]).write(to: firstURL)
        try Data([5, 6, 7, 8, 9]).write(to: secondURL)

        AudioAttachmentStore.attachAudio(
            fileName: firstFileName,
            duration: 4,
            createdAt: entry.date ?? Date(),
            sourceCaptureID: UUID(),
            byteCount: 4,
            codec: "aac-lc",
            to: entry,
            in: sourceContext
        )
        AudioAttachmentStore.attachAudio(
            fileName: secondFileName,
            duration: 5,
            createdAt: (entry.date ?? Date()).addingTimeInterval(60),
            sourceCaptureID: UUID(),
            byteCount: 5,
            codec: "aac-lc",
            to: entry,
            in: sourceContext
        )
        JournalBlockTimelineStore.backfillBlocksIfNeeded(for: entry, in: sourceContext)
        try sourceContext.save()

        let backupURL = try BackupService.shared.exportToJSON(entries: [entry])
        try FileManager.default.removeItem(at: firstURL)
        try FileManager.default.removeItem(at: secondURL)

        let restoreController = PersistenceController(inMemory: true)
        let restoreContext = restoreController.container.viewContext
        let importedCount = try BackupService.shared.importFromJSON(url: backupURL, context: restoreContext)

        #expect(importedCount == 1)
        let restoredEntries = try restoreContext.fetch(DiaryEntry.fetchRequest())
        let restored = try #require(restoredEntries.first)
        let restoredAttachments = (restored.value(forKey: "audioAttachments") as? Set<NSManagedObject>) ?? []
        #expect(restoredAttachments.count == 2)
        #expect(blocks(for: restored, kind: .audio).count == 2)
        #expect(restored.duration == 9)
        #expect(restored.hasStartedEntryAudio)
        let restoredFirstURL = try AudioAttachmentStore.destinationURL(for: firstFileName)
        let restoredSecondURL = try AudioAttachmentStore.destinationURL(for: secondFileName)
        #expect((try? Data(contentsOf: restoredFirstURL)) == Data([1, 2, 3, 4]))
        #expect((try? Data(contentsOf: restoredSecondURL)) == Data([5, 6, 7, 8, 9]))
    }

    private func blocks(for entry: DiaryEntry, kind: JournalBlockKind) -> [JournalBlock] {
        JournalBlockTimelineStore.blocks(for: entry).filter {
            $0.blockKind == kind
        }
    }
}
