//
//  WeeklyReflectionModels.swift
//  OffRecord
//
//  The weekly-reflection vocabulary now lives in ReflectionKit (shared with
//  LifeBoard). This file keeps only the Core Data bridge.
//

import Foundation
@_exported import ReflectionKit

extension WeeklyReflectionEntrySnapshot {
    init?(entry: DiaryEntry) {
        guard let id = entry.id else { return nil }
        let text = (entry.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let date = entry.date ?? entry.createdAt ?? Date()
        let sourceType: WeeklyReflectionSourceType
        if entry.hasStartedEntryAudio {
            sourceType = .voiceTranscript
        } else if entry.hasStartedEntryPhotos {
            sourceType = .photoNote
        } else {
            sourceType = .text
        }
        self.init(
            id: id,
            date: date,
            updatedAt: entry.updatedAt ?? date,
            mood: entry.value(forKey: "mood") as? String,
            text: text,
            sourceType: sourceType
        )
    }
}
