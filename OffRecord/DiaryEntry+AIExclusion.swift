//
//  DiaryEntry+AIExclusion.swift
//  OffRecord
//
//  Per-entry "Keep Out of Friday". The level is stored as the raw value of
//  `JournalAIExclusion` in `DiaryEntry.aiExclusion`; nil means `.included`.
//  Every AI surface checks it at its own gate: the search index, Friday's
//  evidence and profile, proactive cards, and Weekly Reflection.
//

import CoreData
import Foundation
import JournalFoundation

extension DiaryEntry {
    /// How far this entry is kept from Friday and Weekly Reflection.
    var journalAIExclusion: JournalAIExclusion {
        get { aiExclusion.flatMap(JournalAIExclusion.init(rawValue:)) ?? .included }
        set {
            let raw: String? = newValue == .included ? nil : newValue.rawValue
            guard aiExclusion != raw else { return }
            aiExclusion = raw
            // Weekly Reflection, Friday's profile, and proactive cards key their
            // caches on `updatedAt`, so a change here reaches all of them.
            updatedAt = Date()
        }
    }

    /// Matches entries Friday may read: no exclusion stored, or `.included`.
    static var permitsAssistantEvidencePredicate: NSPredicate {
        NSPredicate(format: "aiExclusion == nil OR aiExclusion == %@", JournalAIExclusion.included.rawValue)
    }
}

@MainActor
enum EntryAIExclusionUpdater {
    /// Saves the new level, then brings every AI surface in line right away:
    /// the search index, saved weekly quotes, and Friday's cards. Friday's
    /// profile relearns on its own after the save.
    static func setExclusion(
        _ exclusion: JournalAIExclusion,
        for entry: DiaryEntry,
        in context: NSManagedObjectContext
    ) throws {
        guard entry.journalAIExclusion != exclusion else { return }
        entry.journalAIExclusion = exclusion
        try context.save()

        if exclusion.permitsSemanticIndexing {
            SemanticMemoryIndexController.shared.upsertEntry(entry)
        } else {
            SemanticMemoryIndexController.shared.deleteEntry(id: entry.id)
        }
        if !exclusion.permitsReflectionQuotes, let id = entry.id {
            WeeklyReflectionController.shared.forgetQuotes(fromEntryID: id)
        }

        let request: NSFetchRequest<DiaryEntry> = DiaryEntry.fetchRequest()
        request.predicate = DiaryEntry.startedEntryPredicate
        let started = (try? context.fetch(request)) ?? []
        WeeklyReflectionController.shared.refreshIfNeeded(entries: started)
        if FridayAvailability.isEnabled {
            ProactiveReflectionController.shared.refresh(entries: started)
        }
    }
}
