import Foundation
import Testing
import TranscriptionKit
@testable import OffRecord

@MainActor
struct AudioTranscriptionPersistenceTests {
    @Test func retryUpdatesOneTranscriptBlockAndTracksAttachmentMetadata() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let now = Date()
        let entry = DiaryEntry(context: context)
        entry.id = UUID()
        entry.date = now
        entry.createdAt = now
        entry.updatedAt = now

        let attachment = AudioAttachmentStore.attachAudio(
            fileName: "retry-test.m4a",
            duration: 12,
            createdAt: now,
            sourceCaptureID: nil,
            byteCount: 42,
            codec: "aac-lc",
            to: entry,
            in: context
        )
        AudioAttachmentStore.markTranscriptionProcessing(attachment)
        let first = try #require(
            JournalBlockTimelineStore.upsertTranscriptBlock(
                text: "First result.",
                createdAt: now,
                attachment: attachment,
                to: entry,
                in: context
            )
        )
        AudioAttachmentStore.markTranscriptionCompleted(
            attachment,
            engine: "speechTranscriber",
            locale: Locale(identifier: "en-US"),
            transcriptBlockID: first.blockID
        )

        AudioAttachmentStore.markTranscriptionProcessing(attachment)
        let retried = try #require(
            JournalBlockTimelineStore.upsertTranscriptBlock(
                text: "Corrected result.",
                createdAt: now,
                attachment: attachment,
                to: entry,
                in: context
            )
        )
        AudioAttachmentStore.markTranscriptionCompleted(
            attachment,
            engine: "speechTranscriber",
            locale: Locale(identifier: "en-US"),
            transcriptBlockID: retried.blockID
        )
        try context.save()

        let attachmentID = try #require(attachment.value(forKey: "id") as? UUID)
        let transcriptBlocks = JournalBlockTimelineStore.blocks(for: entry).filter {
            $0.blockKind == .text && $0.audioAttachmentIDValue == attachmentID
        }
        #expect(transcriptBlocks.count == 1)
        #expect(first.blockID == retried.blockID)
        #expect(retried.textValue == "Corrected result.")
        #expect(attachment.value(forKey: "transcriptionAttemptCount") as? Int32 == 2)
        #expect(AudioAttachmentStore.transcriptionStatus(of: attachment) == .completed)
        #expect(attachment.value(forKey: "transcriptionEngine") as? String == "speechTranscriber")
        #expect(entry.entryTranscriptionStatus == .completed)
    }

    @Test func failedAttachmentPreservesRecordingAndErrorState() {
        let context = PersistenceController(inMemory: true).container.viewContext
        let now = Date()
        let entry = DiaryEntry(context: context)
        entry.id = UUID()
        entry.date = now
        entry.createdAt = now
        entry.updatedAt = now
        let attachment = AudioAttachmentStore.attachAudio(
            fileName: "failure-test.m4a",
            duration: 4,
            createdAt: now,
            sourceCaptureID: nil,
            byteCount: 21,
            codec: "aac-lc",
            to: entry,
            in: context
        )

        AudioAttachmentStore.markTranscriptionProcessing(attachment)
        AudioAttachmentStore.markTranscriptionFailed(
            attachment,
            error: TranscriptionError.modelNotInstalled
        )

        #expect(AudioAttachmentStore.audioAttachments(for: entry).count == 1)
        #expect(AudioAttachmentStore.transcriptionStatus(of: attachment) == .failed)
        #expect(attachment.value(forKey: "transcriptionErrorCode") as? String != nil)
        #expect(entry.entryTranscriptionStatus == .failed)
    }
}
