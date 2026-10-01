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
