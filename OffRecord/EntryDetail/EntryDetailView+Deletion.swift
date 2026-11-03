//
//  EntryDetailView+Deletion.swift
//  OffRecord
//
//  Deleting a block or the whole entry (titles for the confirmations, file
//  cleanup after the save), and dropping an empty draft when the view closes.
//

import SwiftUI

extension EntryDetailView {
    func blockDeletionTitle(for kind: JournalBlockKind?) -> String {
        switch kind {
        case .audio: return String(localized: "Delete Recording?")
        case .text: return String(localized: "Delete Text?")
        case .photo: return String(localized: "Delete Photo?")
        case .mood: return String(localized: "Remove Mood?")
        case nil: return String(localized: "Delete?")
        }
    }

    private func removeFilesAfterSuccessfulSave(_ urls: [URL]) {
        for url in urls where FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func deleteBlock(_ item: JournalBlockTimelineItem) {
        guard let block = block(for: item) else { return }
        let plan = JournalBlockTimelineStore.deleteBlock(block, in: viewContext)
        do {
            try viewContext.save()
            removeFilesAfterSuccessfulSave(plan.fileURLsToRemoveAfterSave)
            EntryLearningPipeline.upsertSemanticEntry(entry)
            JournalSpotlightIndexer.shared.upsert(entry: entry)
            HapticManager.shared.entryDeleted()
        } catch {
            viewContext.rollback()
        }
        loadPhotos()
        loadBlocks(backfill: false)
    }

    func deleteWholeDay() {
        isDeletingDay = true
        let plan = JournalBlockTimelineStore.prepareDeleteWholeDay(entry, in: viewContext)
        do {
            try viewContext.save()
            removeFilesAfterSuccessfulSave(plan.fileURLsToRemoveAfterSave)
            if let id = plan.entryID {
                SemanticMemoryIndexController.shared.deleteEntry(id: id)
                JournalSpotlightIndexer.shared.delete(entryID: id)
            }
            HapticManager.shared.entryDeleted()
            dismiss()
        } catch {
            isDeletingDay = false
            viewContext.rollback()
        }
    }

    func deleteEmptyDraftIfNeeded() {
        guard deleteEmptyDraftOnDisappear, entryHasNoContent else { return }

        let id = entry.id
        viewContext.delete(entry)
        do {
            try viewContext.save()
            SemanticMemoryIndexController.shared.deleteEntry(id: id)
            JournalSpotlightIndexer.shared.delete(entryID: id)
        } catch {
            viewContext.rollback()
        }
    }

    private var entryHasNoContent: Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let persistedText = entry.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let duration = entry.value(forKey: "duration") as? Double ?? 0
        let photoCount = entry.photos?.count ?? 0
        let blockCount = journalBlocks.count
        let hasSelectedMood = selectedMood != .none || entry.hasStartedEntryMood
        return trimmed.isEmpty
            && persistedText.isEmpty
            && !hasAudioReference
            && duration <= 0
            && photoCount == 0
            && blockCount == 0
            && !hasSelectedMood
    }
}
