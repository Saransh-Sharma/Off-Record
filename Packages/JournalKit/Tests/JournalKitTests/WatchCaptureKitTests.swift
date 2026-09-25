import Foundation
import Testing
@testable import WatchCaptureKit

struct WatchCaptureTransportTests {
    @Test func recoveryRecordsSeparateRetryableAndQuarantinedFailures() {
        let envelope = WatchCaptureEnvelope(kind: .audio)
        let waiting = WatchCaptureRecoveryRecord(reason: .awaitingAudio, envelope: envelope)
        let incompatible = WatchCaptureRecoveryRecord(
            captureID: envelope.captureID,
            reason: .unsupportedSchema,
            protectedPayload: Data([0x01, 0x02])
        )

        #expect(waiting.captureID == envelope.captureID)
        #expect(waiting.isRetryable)
        #expect(!incompatible.isRetryable)
    }

    @Test func lifeBoardNamespaceRoundTripsWithoutOffRecordKeys() throws {
        let envelope = WatchCaptureEnvelope(
            captureID: UUID(uuidString: "A5000000-0000-0000-0000-000000000001")!,
            kind: .speak,
            createdAtUTC: Date(timeIntervalSince1970: 1_700_000_000),
            sourceSurface: .complication,
            text: "A thought",
            textPreview: "A thought",
            speechTruthState: .transcriptOnWatchNow
        )

        let payload = try envelope.userInfoPayload(namespace: .lifeBoard)
        #expect(payload[WatchCaptureTransportNamespace.lifeBoard.capturePayloadKey] != nil)
        #expect(payload[WatchCaptureTransportNamespace.offRecord.capturePayloadKey] == nil)
        #expect(try WatchCaptureEnvelope.decoded(from: payload, namespace: .lifeBoard) == envelope)
    }

    @Test func lifeBoardImporterAcceptsLegacyOffRecordPayloadDuringMigration() throws {
        let envelope = WatchCaptureEnvelope(
            kind: .mood,
            createdAtUTC: Date(timeIntervalSince1970: 1_700_000_000),
            moodValue: "calm"
        )
        let legacyPayload = try envelope.userInfoPayload()

        let imported = try WatchCaptureEnvelope.decoded(
            from: legacyPayload,
            namespace: .lifeBoard,
            acceptingLegacyNamespaces: [.offRecord]
        )
        #expect(imported == envelope)
    }

    @Test func receiptUsesTheSameNamespacedCompatibilityContract() throws {
        let receipt = WatchCaptureReceipt(
            captureID: UUID(),
            importedEntryID: UUID(),
            importedAtUTC: Date(timeIntervalSince1970: 1_700_000_100),
            kind: .audio
        )
        let payload = try receipt.userInfoPayload(namespace: .lifeBoard)
        #expect(try WatchCaptureReceipt.decoded(from: payload, namespace: .lifeBoard) == receipt)
    }

    @Test func queueBackoffIsBoundedAndRecentProjectionIsStable() {
        #expect(WatchCaptureQueuePolicy.backoffDelay(forAttempt: 1) == 15)
        #expect(WatchCaptureQueuePolicy.backoffDelay(forAttempt: 99) == 1_800)

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let sending = WatchRecentCapture(
            envelope: .init(kind: .speak, textPreview: "Queued"),
            syncState: .sending,
            transferKind: .metadata,
            attemptCount: 1,
            lastAttemptAtUTC: now,
            updatedAtUTC: now
        )
        #expect(!WatchCaptureQueuePolicy.shouldAttemptTransfer(sending, now: now.addingTimeInterval(30)))
        #expect(WatchCaptureQueuePolicy.shouldAttemptTransfer(sending, now: now.addingTimeInterval(121)))
    }
}
