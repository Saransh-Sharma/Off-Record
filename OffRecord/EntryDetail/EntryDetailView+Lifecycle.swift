//
//  EntryDetailView+Lifecycle.swift
//  OffRecord
//
//  What the view does as it opens and closes: syncing text from the store,
//  saving a mood, the Handoff activity, and timestamps on the entry's day.
//

import SwiftUI
import os.log

private let entryDetailLogger = Logger(subsystem: "com.singularity.offrecord", category: "EntryDetail")

extension EntryDetailView {
    func syncTextFromEntry(reason: String, incomingText: String? = nil) {
        let persistedText = incomingText ?? entry.text ?? ""
        guard !isComposingTextBlock && editingBlockObjectID == nil && !isTextFocused else {
            entryDetailLogger.info("Skipped text sync entryID=\(entry.id?.uuidString ?? "missing", privacy: .public) reason=\(reason, privacy: .public) localChars=\(text.count, privacy: .public) persistedChars=\(persistedText.count, privacy: .public) composing=\(isComposingTextBlock, privacy: .public) status=\(entry.entryTranscriptionStatus.rawValue, privacy: .public)")
            return
        }

        guard text != persistedText else { return }

        entryDetailLogger.info("Synced text from entry entryID=\(entry.id?.uuidString ?? "missing", privacy: .public) reason=\(reason, privacy: .public) localChars=\(text.count, privacy: .public) persistedChars=\(persistedText.count, privacy: .public) status=\(entry.entryTranscriptionStatus.rawValue, privacy: .public)")
        text = persistedText
        hasEditedText = false
    }

    func saveIfNeeded() {
        guard !isDeletingDay else { return }
        let currentMood = entry.value(forKey: "mood") as? String ?? ""
        let moodChanged = selectedMood.rawValue != currentMood
        if moodChanged, selectedMood != .none {
            JournalBlockTimelineStore.appendMoodBlock(
                mood: selectedMood,
                createdAt: entryTimestampNow(),
                to: entry,
                in: viewContext
            )
            entry.updatedAt = Date()
            do {
                try viewContext.save()
                EntryLearningPipeline.upsertSemanticEntry(entry)
                JournalSpotlightIndexer.shared.upsert(entry: entry)
                loadBlocks(backfill: false)
            } catch {
                viewContext.rollback()
            }
        }
    }

    func saveMood() {
        JournalBlockTimelineStore.appendMoodBlock(
            mood: selectedMood,
            createdAt: entryTimestampNow(),
            to: entry,
            in: viewContext
        )
        entry.updatedAt = Date()
        HapticManager.shared.moodSelected()
        do {
            try viewContext.save()
            EntryLearningPipeline.upsertSemanticEntry(entry)
            JournalSpotlightIndexer.shared.upsert(entry: entry)
            loadBlocks(backfill: false)
        } catch {
            // ignore
        }
    }

    func startEntryActivity() {
        currentActivity?.resignCurrent()
        currentActivity = JournalSpotlightIndexer.shared.activity(for: entry)
        currentActivity?.becomeCurrent()
    }

    func entryTimestampNow(clock: Date = Date()) -> Date {
        let calendar = Calendar.current
        let base = entry.date ?? clock
        let day = calendar.dateComponents([.year, .month, .day], from: base)
        let time = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: clock)
        var components = DateComponents()
        components.calendar = calendar
        components.year = day.year
        components.month = day.month
        components.day = day.day
        components.hour = time.hour
        components.minute = time.minute
        components.second = time.second
        components.nanosecond = time.nanosecond
        return calendar.date(from: components) ?? clock
    }
}
