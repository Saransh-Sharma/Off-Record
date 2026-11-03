//
//  FridayProfileRebuilder.swift
//  OffRecord
//
//  Friday's profile is derived data. Whenever the journal store saves
//  (locally or from iCloud), the rebuilder compares a fingerprint of the
//  started entries with the one it last learned from and, if they differ,
//  relearns the whole profile from the entries. Edits, deletes, imports,
//  watch captures, and Siri entries all count exactly once, and nothing
//  learned from a deleted entry survives.
//
//  Forget and Rename live in FridayMemoryPreferences and apply on top of
//  whatever the rebuild produces.
//

import CoreData
import CryptoKit
import Foundation
import JournalFoundation
import os.log

private let rebuilderLogger = Logger(subsystem: "com.singularity.offrecord", category: "FridayProfileRebuilder")

/// One entry as Friday learns it: the day's full text, mood, and recording time.
struct FridayLearningInput: Equatable {
    let id: UUID
    let text: String
    let mood: String?
    let date: Date
    let duration: Double
}

extension FridayLearningInput {
    /// Nil for entries without text, entries kept out of Friday, and high-risk
    /// entries, none of which Friday analyzes.
    init?(entry: DiaryEntry) {
        guard let id = entry.id, entry.journalAIExclusion.permitsAssistantEvidence else { return nil }
        let text = (entry.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, JournalRiskClassifier.level(for: text) != .highRiskExcluded else { return nil }
        self.init(
            id: id,
            text: text,
            mood: entry.value(forKey: "mood") as? String,
            date: entry.date ?? entry.createdAt ?? Date(),
            duration: entry.duration
        )
    }

    /// Oldest first, so time-based patterns build up in the order they happened.
    static func learningOrder(_ lhs: FridayLearningInput, _ rhs: FridayLearningInput) -> Bool {
        lhs.date != rhs.date ? lhs.date < rhs.date : lhs.id.uuidString < rhs.id.uuidString
    }
}

extension FridayAssistantEngine {
    /// Learns `inputs` in date order, one call per entry.
    func learn(from inputs: [FridayLearningInput]) {
        for input in inputs.sorted(by: FridayLearningInput.learningOrder) {
            learn(input)
        }
    }

    func learn(_ input: FridayLearningInput) {
        processEntry(text: input.text, mood: input.mood, date: input.date, duration: input.duration)
    }
}

enum FridayProfileFingerprint {
    /// Bump when the learning rules change so every device relearns once.
    static let version = 1

    /// Order-independent: the same entries with the same edit times always match.
    static func make(_ entries: [(id: UUID, updatedAt: Date?)]) -> String {
        let lines = entries
            .map { "\($0.id.uuidString)|\(Int64((($0.updatedAt ?? .distantPast).timeIntervalSince1970 * 1000).rounded()))" }
            .sorted()
        let digest = SHA256.hash(data: Data((["v\(version)"] + lines).joined(separator: "\n").utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor
final class FridayProfileRebuilder {
    static let shared = FridayProfileRebuilder()

    private static let fingerprintKey = "offrecord_friday_profile_fingerprint"

    private var container: NSPersistentContainer?
    private var observers: [NSObjectProtocol] = []
    private var pending: Task<Void, Never>?

    /// True once started; fixture runs never start it.
    var isActive: Bool { container != nil }

    private init() {}

    func start(container: NSPersistentContainer) {
        guard self.container == nil else { return }
        let arguments = ProcessInfo.processInfo.arguments
        // UI tests and screenshots seed Friday directly and need a stable profile.
        guard !arguments.contains("-UITesting"), !arguments.contains("-ScreenshotMode") else { return }
        self.container = container

        observers += StoreChangeObservation.observe(container.persistentStoreCoordinator) { [weak self] in
            self?.scheduleRefresh()
        }

        scheduleRefresh(after: .seconds(3))
    }

    /// Coalesces bursts of saves into one check. Friday's own saves leave the
    /// fingerprint unchanged, so they never trigger a rebuild.
    func scheduleRefresh(after delay: Duration = .seconds(2), force: Bool = false) {
        // While Friday is off she learns nothing.
        guard isActive, FridayAvailability.isEnabled else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.refreshIfNeeded(force: force)
        }
    }

    /// Relearns now, even if nothing changed. Settings uses this.
    func rebuildNow() {
        scheduleRefresh(after: .zero, force: true)
    }

    /// Stops any pending pass and forgets the fingerprint, so the next start relearns.
    func cancelPendingRefresh() {
        pending?.cancel()
        pending = nil
        UserDefaults.standard.removeObject(forKey: Self.fingerprintKey)
    }

    private func refreshIfNeeded(force: Bool) async {
        guard let container else { return }
        let fingerprint = await Self.currentFingerprint(container: container)
        let stored = UserDefaults.standard.string(forKey: Self.fingerprintKey)
        guard force || fingerprint != stored else { return }
        await rebuild(fingerprint: fingerprint, context: container.viewContext)
    }

    /// What a rebuild learns from: every started entry with text, oldest first.
    static func learningInputs(in context: NSManagedObjectContext) -> [FridayLearningInput] {
        let request: NSFetchRequest<DiaryEntry> = DiaryEntry.fetchRequest()
        request.predicate = DiaryEntry.startedEntryPredicate
        let entries = (try? context.fetch(request)) ?? []
        return entries.compactMap(FridayLearningInput.init(entry:)).sorted(by: FridayLearningInput.learningOrder)
    }

    private func rebuild(fingerprint: String, context: NSManagedObjectContext) async {
        let inputs = Self.learningInputs(in: context)

        let token = PerformanceSignposts.begin("FridayRebuild")
        defer { PerformanceSignposts.end(token) }
        let scratch = FridayAssistantEngine.makeScratch()
        for input in inputs {
            // A newer save cancels this pass; the next one starts from scratch.
            guard !Task.isCancelled else { return }
            scratch.learn(input)
            await Task.yield()
        }
        guard !Task.isCancelled, FridayAvailability.isEnabled else { return }

        FridayAssistantEngine.shared.adoptProfile(from: scratch)
        UserDefaults.standard.set(fingerprint, forKey: Self.fingerprintKey)
        rebuilderLogger.notice("Friday profile rebuilt from \(inputs.count, privacy: .public) entries.")
    }

    nonisolated static func currentFingerprint(container: NSPersistentContainer) async -> String {
        let context = container.newBackgroundContext()
        return await context.perform {
            let request = NSFetchRequest<NSDictionary>(entityName: "DiaryEntry")
            request.predicate = DiaryEntry.startedEntryPredicate
            request.resultType = .dictionaryResultType
            request.propertiesToFetch = ["id", "updatedAt", "aiExclusion"]
            // Entries kept out of Friday aren't learned, so they aren't part of the fingerprint.
            let rows = ((try? context.fetch(request)) ?? []).filter { row in
                let raw = row["aiExclusion"] as? String
                return raw == nil || raw == JournalAIExclusion.included.rawValue
            }
            let entries: [(id: UUID, updatedAt: Date?)] = rows.compactMap { row in
                guard let id = row["id"] as? UUID else { return nil }
                return (id: id, updatedAt: row["updatedAt"] as? Date)
            }
            return FridayProfileFingerprint.make(entries)
        }
    }
}
