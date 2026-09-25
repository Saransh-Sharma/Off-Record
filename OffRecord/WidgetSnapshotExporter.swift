//
//  WidgetSnapshotExporter.swift
//  OffRecord
//
//  Keeps the App Group widget snapshot in step with the journal. Whenever the
//  journal store saves (locally or from iCloud), it rebuilds a metadata-only
//  summary — day keys, mood raw values, counts — and reloads widgets only when
//  that summary actually changed. Journal text never leaves the store.
//

import CoreData
import Foundation
import WidgetKit
import os.log

private let exporterLogger = Logger(subsystem: "com.singularity.offrecord", category: "WidgetSnapshot")

@MainActor
final class WidgetSnapshotExporter {
    static let shared = WidgetSnapshotExporter()

    /// Enough history for a full "year in pixels" grid plus long streaks.
    nonisolated private static let historyDays = 800

    private var container: NSPersistentContainer?
    private var observers: [NSObjectProtocol] = []
    private var pendingExport: Task<Void, Never>?

    private init() {}

    func start(container: NSPersistentContainer) {
        guard self.container == nil else { return }
        self.container = container

        let coordinator = container.persistentStoreCoordinator
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .NSManagedObjectContextDidSave, object: nil, queue: .main) { [weak self] note in
            guard let context = note.object as? NSManagedObjectContext,
                  context.persistentStoreCoordinator === coordinator else { return }
            MainActor.assumeIsolated { self?.scheduleExport() }
        })
        observers.append(center.addObserver(forName: .NSPersistentStoreRemoteChange, object: coordinator, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleExport() }
        })

        scheduleExport(after: .seconds(2))
    }

    /// Coalesces bursts of saves (recording, transcription, mood) into one export.
    func scheduleExport(after delay: Duration = .milliseconds(1200)) {
        pendingExport?.cancel()
        pendingExport = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.exportNow()
        }
    }

    func exportNow() async {
        guard let container else { return }
        pendingExport?.cancel()
        pendingExport = nil

        guard let snapshot = await Self.buildSnapshot(container: container) else { return }
        if WidgetSnapshotStore.save(snapshot) {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    nonisolated private static func buildSnapshot(container: NSPersistentContainer) async -> WidgetSnapshot? {
        let context = container.newBackgroundContext()
        return await context.perform {
            let calendar = Calendar.current
            let now = Date()
            let startOfToday = calendar.startOfDay(for: now)
            guard let cutoff = calendar.date(byAdding: .day, value: -historyDays, to: startOfToday),
                  let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) else {
                return nil
            }

            do {
                let started = DiaryEntry.startedEntryPredicate

                let daysRequest = NSFetchRequest<NSDictionary>(entityName: "DiaryEntry")
                daysRequest.resultType = .dictionaryResultType
                daysRequest.propertiesToFetch = ["date", "mood"]
                daysRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                    started,
                    NSPredicate(format: "date >= %@", cutoff as NSDate)
                ])
                daysRequest.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: true)]

                var days: [String: String] = [:]
                for row in try context.fetch(daysRequest) {
                    guard let date = row["date"] as? Date else { continue }
                    let key = WidgetDayKey.key(for: date, calendar: calendar)
                    let mood = ((row["mood"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !mood.isEmpty {
                        // Rows are ordered by last update, so the latest mood of the day wins.
                        days[key] = mood
                    } else if days[key] == nil {
                        days[key] = ""
                    }
                }

                let countRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "DiaryEntry")
                countRequest.predicate = started
                let total = try context.count(for: countRequest)

                let todayRequest: NSFetchRequest<DiaryEntry> = DiaryEntry.fetchRequest()
                todayRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                    started,
                    NSPredicate(format: "date >= %@ AND date < %@", startOfToday as NSDate, startOfTomorrow as NSDate)
                ])
                let todayEntries = try context.fetch(todayRequest)

                return WidgetSnapshot(
                    days: days,
                    totalEntries: total,
                    todayKey: WidgetDayKey.key(for: now, calendar: calendar),
                    todayWordCount: todayEntries.reduce(0) { $0 + $1.startedEntryWordCount },
                    todayHasVoice: todayEntries.contains { $0.hasStartedEntryAudio }
                )
            } catch {
                exporterLogger.error("Widget snapshot fetch failed: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
    }
}
