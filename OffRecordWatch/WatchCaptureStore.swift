import Foundation
import os.log
import SwiftUI

private let watchStoreLogger = Logger(subsystem: "com.singularity.offrecord.watch", category: "CaptureStore")

@MainActor
final class WatchCaptureStore: ObservableObject {
    static let shared = WatchCaptureStore()

    @Published private(set) var outbox: [WatchRecentCapture] = []
    @Published var showPreviews: Bool {
        didSet {
            defaults.set(showPreviews, forKey: Self.showPreviewsKey)
        }
    }

    private let connectivity = WatchConnectivityCoordinator.shared
    private let defaults = UserDefaults.standard
    private let widgetDefaults = UserDefaults(suiteName: "group.com.singularity.offrecord")
    private static let showPreviewsKey = "offrecord.watch.showPreviews"
    private static let widgetQueueCountKey = "offrecord.watch.queueCount"
    private static let syncedRecentRetention = 20
    private static let metadataRetentionLimit = 200
    private static let audioFileRetentionLimit = 25
    private static let audioByteRetentionLimit: Int64 = 150 * 1024 * 1024

    private init() {
        showPreviews = defaults.bool(forKey: Self.showPreviewsKey)
        outbox = load()
        applyStoragePolicy()
        widgetDefaults?.set(queueCount, forKey: Self.widgetQueueCountKey)
        connectivity.onReceipt = { [weak self] receipt in
            self?.markSynced(receipt)
        }
    }

    var captures: [WatchRecentCapture] {
        WatchCaptureQueuePolicy.recentProjection(from: outbox)
    }

    var queueCount: Int {
        outbox.filter { $0.syncState != .synced }.count
    }

    var syncLine: String {
        if queueCount == 0 {
            return "Synced to iPhone"
        }
        if connectivity.isReachable {
            return "\(queueCount) sending to iPhone"
        }
        return "\(queueCount) saved on watch"
    }

    func start() {
        connectivity.start()
        retryPending()
    }

    func saveMood(_ mood: WatchMoodValue, source: WatchCaptureSourceSurface = .app) {
        let envelope = WatchCaptureEnvelope(
            kind: .mood,
            sourceSurface: source,
            moodValue: mood.rawValue,
            textPreview: mood.displayName
        )
        enqueue(envelope)
        WatchHaptics.success()
    }

    func saveSpeakText(_ text: String, source: WatchCaptureSourceSurface = .app) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let envelope = WatchCaptureEnvelope(
            kind: .speak,
            sourceSurface: source,
            text: String(trimmed.prefix(500)),
            textPreview: String(trimmed.prefix(64)),
            speechTruthState: .transcriptOnWatchNow
        )
        enqueue(envelope)
        WatchHaptics.success()
    }

    func saveAudio(fileURL: URL, duration: TimeInterval, source: WatchCaptureSourceSurface = .app) {
        let captureID = UUID()
        let byteCount = ((try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size]) as? NSNumber)?.int64Value ?? 0
        let manifest = WatchAudioManifest(
            captureID: captureID,
            fileName: fileURL.lastPathComponent,
            duration: duration,
            byteCount: byteCount
        )
        let envelope = WatchCaptureEnvelope(
            captureID: captureID,
            kind: .audio,
            sourceSurface: source,
            textPreview: "Audio only",
            speechTruthState: .audioOnly,
            audioManifest: manifest
        )
        enqueue(envelope, audioFileURL: fileURL)
        WatchHaptics.success()
    }

    func retryPending() {
        let now = Date()
        for item in outbox where shouldAttemptTransfer(item, now: now) {
            send(item)
        }
    }

    func preview(for item: WatchRecentCapture) -> String {
        if showPreviews {
            return item.envelope.privacySafePreview
        }
        switch item.envelope.kind {
        case .mood:
            return item.envelope.moodValue.flatMap { WatchMoodValue(rawValue: $0)?.displayName } ?? "Mood"
        case .speak:
            return "Private thought"
        case .audio:
            if let duration = item.envelope.audioManifest?.duration {
                return "Audio \(Self.durationFormatter.string(from: duration) ?? "")"
            }
            return "Audio note"
        }
    }

    private func enqueue(_ envelope: WatchCaptureEnvelope, audioFileURL: URL? = nil) {
        let item = WatchRecentCapture(
            envelope: envelope,
            syncState: .queued,
            transferKind: audioFileURL == nil ? .metadata : .audioFile,
            updatedAtUTC: Date()
        )
        outbox.removeAll { $0.envelope.captureID == envelope.captureID }
        outbox.insert(item, at: 0)
        applyStoragePolicy()
        persist()

        send(item, knownAudioURL: audioFileURL)
    }

    private func send(_ item: WatchRecentCapture, knownAudioURL: URL? = nil) {
        let envelope = item.envelope
        if envelope.kind == .audio {
            guard let fileURL = knownAudioURL ?? audioFileURL(for: envelope),
                  FileManager.default.fileExists(atPath: fileURL.path) else {
                markFailed(envelope.captureID, message: "Audio file missing.", missingFile: true)
                return
            }
            markTransferAttempt(for: envelope.captureID, kind: .audioFile)
            connectivity.transferAudio(fileURL: fileURL, envelope: envelope)
            return
        }

        markTransferAttempt(for: envelope.captureID, kind: .metadata)
        connectivity.transfer(envelope)
    }

    private func markSynced(_ receipt: WatchCaptureReceipt) {
        if let item = outbox.first(where: { $0.envelope.captureID == receipt.captureID }),
           item.envelope.kind == .audio,
           let fileURL = audioFileURL(for: item.envelope) {
            try? FileManager.default.removeItem(at: fileURL)
        }
        updateState(for: receipt.captureID, state: .synced)
        applyStoragePolicy()
        persist()
    }

    private func updateState(for captureID: UUID, state: WatchSyncState) {
        guard let index = outbox.firstIndex(where: { $0.envelope.captureID == captureID }) else { return }
        outbox[index].syncState = state
        outbox[index].updatedAtUTC = Date()
        if state == .synced {
            outbox[index].nextAttemptAtUTC = nil
            outbox[index].lastError = nil
            outbox[index].audioFileMissing = false
        }
        persist()
    }

    private func markTransferAttempt(for captureID: UUID, kind: WatchTransferKind) {
        guard let index = outbox.firstIndex(where: { $0.envelope.captureID == captureID }) else { return }
        let now = Date()
        outbox[index].syncState = .sending
        outbox[index].transferKind = kind
        outbox[index].attemptCount += 1
        outbox[index].lastAttemptAtUTC = now
        outbox[index].nextAttemptAtUTC = now.addingTimeInterval(backoffDelay(forAttempt: outbox[index].attemptCount))
        outbox[index].lastError = nil
        outbox[index].updatedAtUTC = now
        persist()
    }

    private func markFailed(_ captureID: UUID, message: String, missingFile: Bool = false) {
        guard let index = outbox.firstIndex(where: { $0.envelope.captureID == captureID }) else { return }
        let now = Date()
        outbox[index].syncState = .failed
        outbox[index].lastError = message
        outbox[index].audioFileMissing = missingFile
        outbox[index].nextAttemptAtUTC = missingFile ? nil : now.addingTimeInterval(backoffDelay(forAttempt: outbox[index].attemptCount))
        outbox[index].updatedAtUTC = now
        persist()
    }

    private func shouldAttemptTransfer(_ item: WatchRecentCapture, now: Date) -> Bool {
        WatchCaptureQueuePolicy.shouldAttemptTransfer(item, now: now)
    }

    private func backoffDelay(forAttempt attempt: Int) -> TimeInterval {
        WatchCaptureQueuePolicy.backoffDelay(forAttempt: attempt)
    }

    private func audioFileURL(for envelope: WatchCaptureEnvelope) -> URL? {
        guard envelope.kind == .audio, let fileName = envelope.audioManifest?.fileName else { return nil }
        return WatchAudioRecorder.recordingsDirectory().appendingPathComponent(fileName)
    }

    private func applyStoragePolicy() {
        outbox.sort { $0.updatedAtUTC > $1.updatedAtUTC }

        var syncedSeen = 0
        outbox.removeAll { item in
            guard item.syncState == .synced else { return false }
            syncedSeen += 1
            return syncedSeen > Self.syncedRecentRetention
        }

        if outbox.count > Self.metadataRetentionLimit {
            let protected = outbox.filter { $0.syncState != .synced }
            let synced = outbox.filter { $0.syncState == .synced }
            outbox = Array((protected + synced).prefix(max(Self.metadataRetentionLimit, protected.count)))
        }

        purgeSyncedAndOrphanedAudioFiles()
    }

    private func purgeSyncedAndOrphanedAudioFiles() {
        let unsyncedAudioNames = Set(outbox.compactMap { item -> String? in
            guard item.syncState != .synced, item.envelope.kind == .audio else { return nil }
            return item.envelope.audioManifest?.fileName
        })
        let directory = WatchAudioRecorder.recordingsDirectory()
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        var retained: [(url: URL, date: Date, size: Int64)] = []
        for url in urls {
            if unsyncedAudioNames.contains(url.lastPathComponent) {
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                retained.append((url, values?.contentModificationDate ?? Date.distantPast, Int64(values?.fileSize ?? 0)))
            } else {
                try? FileManager.default.removeItem(at: url)
            }
        }

        retained.sort { $0.date > $1.date }
        var totalBytes: Int64 = 0
        for (index, file) in retained.enumerated() {
            totalBytes += file.size
            if index >= Self.audioFileRetentionLimit || totalBytes > Self.audioByteRetentionLimit {
                if let captureIndex = outbox.firstIndex(where: { $0.envelope.audioManifest?.fileName == file.url.lastPathComponent }) {
                    outbox[captureIndex].syncState = .failed
                    outbox[captureIndex].lastError = "Storage limit reached."
                    outbox[captureIndex].updatedAtUTC = Date()
                }
            }
        }
    }

    private func persist() {
        widgetDefaults?.set(queueCount, forKey: Self.widgetQueueCountKey)
        do {
            let data = try JSONEncoder.watchCapture.encode(outbox)
            try data.write(to: storeURL, options: [.atomic])
        } catch {
            watchStoreLogger.warning("Could not persist watch captures: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func load() -> [WatchRecentCapture] {
        guard let data = try? Data(contentsOf: storeURL) else { return [] }
        return (try? JSONDecoder.watchCapture.decode([WatchRecentCapture].self, from: data)) ?? []
    }

    private var storeURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory.appendingPathComponent("WatchQuickCaptures.json")
    }

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter
    }()
}
