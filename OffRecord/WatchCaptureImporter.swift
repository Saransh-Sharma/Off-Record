import CoreData
import Foundation
import os.log

#if canImport(WatchConnectivity)
@preconcurrency import WatchConnectivity
#endif

private let watchCaptureLogger = Logger(subsystem: "com.singularity.offrecord", category: "WatchQuickCapture")

private enum WatchCaptureImportError: LocalizedError {
    case pendingAudioFile(UUID)
    case missingAudioFile(UUID)

    var errorDescription: String? {
        switch self {
        case .pendingAudioFile(let captureID):
            return "Waiting for watch audio file \(captureID.uuidString)."
        case .missingAudioFile(let captureID):
            return "Watch audio file missing for \(captureID.uuidString)."
        }
    }
}

@MainActor
final class WatchCaptureImporter: NSObject {
    static let shared = WatchCaptureImporter()

    private var context: NSManagedObjectContext?
    private var pendingAudioCaptureIDs = Set<UUID>()

    private override init() {
        super.init()
    }

    func start(context: NSManagedObjectContext) {
        self.context = context

        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else {
            watchCaptureLogger.info("WatchConnectivity is not supported on this device.")
            return
        }

        let session = WCSession.default
        if session.delegate !== self {
            session.delegate = self
        }
        session.activate()
        watchCaptureLogger.info("Watch Quick Capture importer activated.")
        #endif
    }

    @discardableResult
    func importForTesting(_ envelope: WatchCaptureEnvelope, audioFileURL: URL? = nil) throws -> UUID {
        guard let context else {
            throw NSError(
                domain: "WatchCaptureImporter",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Importer has not been started."]
            )
        }
        return try importEnvelope(envelope, audioFileURL: audioFileURL, in: context)
    }

    func receiveFileForTesting(at url: URL, metadata: [String: Any]) {
        receiveFile(at: url, metadata: metadata)
    }

    private func importEnvelope(
        _ envelope: WatchCaptureEnvelope,
        audioFileURL: URL?,
        in context: NSManagedObjectContext
    ) throws -> UUID {
        if let existingEntryID = try existingReceiptEntryID(for: envelope.captureID, in: context) {
            sendReceipt(captureID: envelope.captureID, importedEntryID: existingEntryID, kind: envelope.kind)
            return existingEntryID
        }

        if envelope.kind == .audio, audioFileURL == nil {
            pendingAudioCaptureIDs.insert(envelope.captureID)
            throw WatchCaptureImportError.pendingAudioFile(envelope.captureID)
        }

        let entry = try DiaryEntryDailyStore.getOrCreateEntry(on: envelope.createdAtUTC, in: context)
        var importedAudioURL: URL?
        switch envelope.kind {
        case .mood:
            if let rawMood = envelope.moodValue, let mood = Mood(rawValue: rawMood), mood != .none {
                JournalBlockTimelineStore.appendMoodBlock(
                    mood: mood,
                    createdAt: envelope.createdAtUTC,
                    to: entry,
                    in: context
                )
            }
        case .speak:
            if let text = envelope.text {
                JournalBlockTimelineStore.appendTextBlock(
                    text: text,
                    createdAt: envelope.createdAtUTC,
                    to: entry,
                    in: context,
                    sourceCaptureID: envelope.captureID
                )
            }
        case .audio:
            importedAudioURL = try importAudio(envelope: envelope, audioFileURL: audioFileURL, into: entry, in: context)
        }

        let entryID = ensureEntryID(entry)
        try createReceipt(for: envelope, importedEntryID: entryID, in: context)
        try save(context)
        pendingAudioCaptureIDs.remove(envelope.captureID)

        EntryLearningPipeline.upsertSemanticEntry(entry)
        JournalSpotlightIndexer.shared.upsert(entry: entry)
        sendReceipt(captureID: envelope.captureID, importedEntryID: entryID, kind: envelope.kind)

        if envelope.kind == .audio, SpeechTranscriptionConsent.hasGrantedAppleSpeechProcessing, let importedAudioURL {
            transcribeImportedAudio(importedAudioURL, entryObjectID: entry.objectID, envelope: envelope, context: context)
        }

        watchCaptureLogger.info("Imported watch capture kind=\(envelope.kind.rawValue, privacy: .public) captureID=\(envelope.captureID.uuidString, privacy: .public)")
        return entryID
    }

    private func importAudio(
        envelope: WatchCaptureEnvelope,
        audioFileURL: URL?,
        into entry: DiaryEntry,
        in context: NSManagedObjectContext
    ) throws -> URL? {
        guard let manifest = envelope.audioManifest else {
            return nil
        }

        if try AudioAttachmentStore.attachmentExists(sourceCaptureID: envelope.captureID, in: context) {
            var existingURL: URL?
            if let existingAttachment = AudioAttachmentStore.audioAttachment(sourceCaptureID: envelope.captureID, in: context) {
                JournalBlockTimelineStore.appendAudioBlock(
                    attachment: existingAttachment,
                    createdAt: manifest.createdAtUTC,
                    sourceCaptureID: envelope.captureID,
                    to: entry,
                    in: context
                )
                existingURL = AudioAttachmentStore.audioURL(for: existingAttachment)
            }
            if let audioFileURL {
                try? FileManager.default.removeItem(at: audioFileURL)
            }
            return existingURL
        }

        guard let audioFileURL,
              FileManager.default.fileExists(atPath: audioFileURL.path) else {
            throw WatchCaptureImportError.missingAudioFile(envelope.captureID)
        }

        let finalURL: URL
        let fileName = sanitizedAudioFileName(for: envelope, manifest: manifest)
        finalURL = try AudioAttachmentStore.destinationURL(for: fileName)
        if FileManager.default.fileExists(atPath: finalURL.path) {
            try? FileManager.default.removeItem(at: finalURL)
        }
        try FileManager.default.moveItem(at: audioFileURL, to: finalURL)

        let byteCount = ((try? FileManager.default.attributesOfItem(atPath: finalURL.path)[.size]) as? NSNumber)?.int64Value ?? manifest.byteCount
        let attachment = AudioAttachmentStore.attachAudio(
            fileName: finalURL.lastPathComponent,
            duration: manifest.duration,
            createdAt: manifest.createdAtUTC,
            sourceCaptureID: envelope.captureID,
            byteCount: byteCount,
            codec: manifest.codec,
            to: entry,
            in: context
        )
        JournalBlockTimelineStore.appendAudioBlock(
            attachment: attachment,
            createdAt: manifest.createdAtUTC,
            sourceCaptureID: envelope.captureID,
            to: entry,
            in: context
        )

        if !SpeechTranscriptionConsent.hasGrantedAppleSpeechProcessing {
            entry.entryTranscriptionStatus = .none
        }
        return finalURL
    }

    private func transcribeImportedAudio(
        _ audioFileURL: URL,
        entryObjectID: NSManagedObjectID,
        envelope: WatchCaptureEnvelope,
        context: NSManagedObjectContext
    ) {
        if let entry = try? context.existingObject(with: entryObjectID) as? DiaryEntry {
            entry.entryTranscriptionStatus = .processing
            try? context.save()
        }

        SpeechTranscriber.shared.transcribe(from: audioFileURL) { result in
            Task { @MainActor in
                guard let entry = try? context.existingObject(with: entryObjectID) as? DiaryEntry else {
                    watchCaptureLogger.info("Skipped watch audio transcript because entry was deleted.")
                    return
                }
                switch result {
                case .success(let text):
                    JournalBlockTimelineStore.appendTextBlock(
                        text: text,
                        createdAt: envelope.audioManifest?.createdAtUTC ?? envelope.createdAtUTC,
                        to: entry,
                        in: context,
                        sourceCaptureID: envelope.captureID
                    )
                    entry.entryTranscriptionStatus = .completed
                    entry.updatedAt = Date()
                    do {
                        try context.save()
                        EntryLearningPipeline.upsertSemanticEntry(entry)
                        JournalSpotlightIndexer.shared.upsert(entry: entry)
                    } catch {
                        watchCaptureLogger.error("Failed to save watch audio transcript: \(error.localizedDescription, privacy: .public)")
                    }
                case .failure(let error):
                    entry.entryTranscriptionStatus = .failed
                    entry.updatedAt = Date()
                    try? context.save()
                    watchCaptureLogger.warning("Watch audio transcription failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    private func existingReceiptEntryID(for captureID: UUID, in context: NSManagedObjectContext) throws -> UUID? {
        let request = NSFetchRequest<NSManagedObject>(entityName: "WatchImportReceipt")
        request.predicate = NSPredicate(format: "captureID == %@", captureID as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first?.value(forKey: "importedEntryID") as? UUID
    }

    private func createReceipt(
        for envelope: WatchCaptureEnvelope,
        importedEntryID: UUID,
        in context: NSManagedObjectContext
    ) throws {
        let receipt = NSEntityDescription.insertNewObject(forEntityName: "WatchImportReceipt", into: context)
        receipt.setValue(envelope.captureID, forKey: "captureID")
        receipt.setValue(importedEntryID, forKey: "importedEntryID")
        receipt.setValue(Date(), forKey: "importedAt")
        receipt.setValue(envelope.kind.rawValue, forKey: "kind")
        receipt.setValue("\(envelope.schemaVersion)-\(envelope.kind.rawValue)", forKey: "importHash")
    }

    private func ensureEntryID(_ entry: DiaryEntry) -> UUID {
        if let id = entry.id {
            return id
        }
        let id = UUID()
        entry.id = id
        return id
    }

    private func save(_ context: NSManagedObjectContext) throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    private func sanitizedAudioFileName(for envelope: WatchCaptureEnvelope, manifest: WatchAudioManifest) -> String {
        let ext = (manifest.fileName as NSString).pathExtension
        let suffix = ext.isEmpty ? "m4a" : ext
        return "watch-\(envelope.captureID.uuidString).\(suffix)"
    }

    private func sendReceipt(captureID: UUID, importedEntryID: UUID, kind: WatchCaptureKind) {
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else { return }
        let receipt = WatchCaptureReceipt(
            captureID: captureID,
            importedEntryID: importedEntryID,
            importedAtUTC: Date(),
            kind: kind
        )
        do {
            WCSession.default.transferUserInfo(try receipt.userInfoPayload())
        } catch {
            watchCaptureLogger.warning("Could not encode watch import receipt: \(error.localizedDescription, privacy: .public)")
        }
        #endif
    }

    private func receiveUserInfo(_ userInfo: [String: Any]) {
        do {
            if let _ = try? WatchCaptureReceipt.decoded(from: userInfo) {
                return
            }
            let envelope = try WatchCaptureEnvelope.decoded(from: userInfo)
            guard let context else { return }
            _ = try importEnvelope(envelope, audioFileURL: nil, in: context)
        } catch {
            if error is WatchCaptureImportError {
                watchCaptureLogger.info("Deferred watch capture metadata: \(error.localizedDescription, privacy: .public)")
            } else {
                watchCaptureLogger.error("Failed to import watch capture metadata: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func receiveFile(at url: URL, metadata: [String: Any]?) {
        var stagingURL: URL?
        do {
            guard let metadata, let envelope = try? WatchCaptureEnvelope.decoded(from: metadata) else {
                watchCaptureLogger.warning("Watch audio file arrived without decodable metadata.")
                return
            }

            guard let context else { return }
            if let existingEntryID = try existingReceiptEntryID(for: envelope.captureID, in: context) {
                try? FileManager.default.removeItem(at: url)
                sendReceipt(captureID: envelope.captureID, importedEntryID: existingEntryID, kind: envelope.kind)
                return
            }

            let stagingName = "watch-staged-\(envelope.captureID.uuidString)-\(url.lastPathComponent)"
            let targetURL = FileManager.default.temporaryDirectory.appendingPathComponent(stagingName)
            stagingURL = targetURL
            if FileManager.default.fileExists(atPath: targetURL.path) {
                try? FileManager.default.removeItem(at: targetURL)
            }
            try FileManager.default.moveItem(at: url, to: targetURL)

            _ = try importEnvelope(envelope, audioFileURL: targetURL, in: context)
        } catch {
            if let stagingURL, FileManager.default.fileExists(atPath: stagingURL.path) {
                try? FileManager.default.removeItem(at: stagingURL)
            }
            watchCaptureLogger.error("Failed to import watch capture file: \(error.localizedDescription, privacy: .public)")
        }
    }
}

#if canImport(WatchConnectivity)
extension WatchCaptureImporter: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            watchCaptureLogger.warning("WatchConnectivity activation failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in
            WatchCaptureImporter.shared.receiveUserInfo(userInfo)
        }
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let fileURL = file.fileURL
        let metadata = file.metadata
        let stagedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("watch-session-\(UUID().uuidString)-\(fileURL.lastPathComponent)")
        do {
            if FileManager.default.fileExists(atPath: stagedURL.path) {
                try? FileManager.default.removeItem(at: stagedURL)
            }
            try FileManager.default.moveItem(at: fileURL, to: stagedURL)
        } catch {
            watchCaptureLogger.error("Failed to stage watch capture file: \(error.localizedDescription, privacy: .public)")
            return
        }

        Task { @MainActor in
            WatchCaptureImporter.shared.receiveFile(at: stagedURL, metadata: metadata)
        }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif
}
#endif
