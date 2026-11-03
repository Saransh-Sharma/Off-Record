//
//  EntryDetailView+Editing.swift
//  OffRecord
//
//  Writing a new text block and editing an existing one: what is being
//  edited, whether it can be saved, and starting, saving, and cancelling.
//

import SwiftUI

extension EntryDetailView {
    // MARK: - Computed Properties

    var isActivelyEditing: Bool {
        isComposingTextBlock || editingBlockObjectID != nil
    }

    private var activeEditingItem: JournalBlockTimelineItem? {
        guard let editingBlockObjectID else { return nil }
        return timelineItems.first { $0.id == editingBlockObjectID }
    }

    var canSaveActiveEditing: Bool {
        if isComposingTextBlock {
            return !newTextBlockText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if editingBlockObjectID != nil {
            return !editingBlockText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return false
    }

    var activeWordCount: Int {
        if isComposingTextBlock {
            return wordCount(for: newTextBlockText)
        }
        if editingBlockObjectID != nil {
            return wordCount(for: editingBlockText)
        }
        return wordCount
    }

    private var wordCount: Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }

    private var characterCount: Int {
        text.count
    }

    private var editableTextBinding: Binding<String> {
        Binding(
            get: { text },
            set: { newValue in
                if text != newValue {
                    text = newValue
                    hasEditedText = true
                }
            }
        )
    }

    private func wordCount(for value: String) -> Int {
        value.split { $0.isWhitespace || $0.isNewline }.count
    }

    // MARK: - Actions

    private func toggleEditingMode() {
        if isComposingTextBlock {
            cancelNewTextBlock()
        } else {
            beginNewTextBlock()
        }
    }

    func saveActiveEditing() {
        if isComposingTextBlock {
            _ = saveNewTextBlock()
        } else if let activeEditingItem {
            _ = finishEditingBlock(activeEditingItem)
        }
    }

    func cancelActiveEditing() {
        if isComposingTextBlock {
            cancelNewTextBlock()
        } else {
            cancelEditingBlock()
        }
    }

    private func cancelEditingBlock() {
        isTextFocused = false
        editingBlockObjectID = nil
        editingBlockText = ""
        blockEditError = nil
    }

    func savePendingEditsBeforeExit() -> Bool {
        var didSave = true

        if let activeEditingItem {
            let trimmed = editingBlockText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                cancelEditingBlock()
            } else {
                didSave = finishEditingBlock(activeEditingItem) && didSave
            }
        }

        if isComposingTextBlock {
            let trimmed = newTextBlockText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                cancelNewTextBlock()
                return didSave
            }
            didSave = saveNewTextBlock() && didSave
        }

        return didSave
    }

    func beginNewTextBlock() {
        if editingBlockObjectID != nil {
            guard savePendingEditsBeforeExit() else { return }
        }
        newTextBlockText = ""
        newTextBlockError = nil
        isComposingTextBlock = true
        isTextFocused = true
        HapticManager.shared.selectionChanged()
    }

    private func cancelNewTextBlock() {
        isTextFocused = false
        composerPrompt = nil
        isComposingTextBlock = false
        newTextBlockText = ""
        newTextBlockError = nil
    }

    @discardableResult
    private func saveNewTextBlock() -> Bool {
        let trimmed = newTextBlockText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            newTextBlockError = String(localized: "Write something first.")
            return false
        }

        JournalBlockTimelineStore.appendTextBlock(
            text: trimmed,
            createdAt: entryTimestampNow(),
            to: entry,
            in: viewContext
        )
        do {
            try viewContext.save()
            EntryLearningPipeline.processSavedEntry(
                text: trimmed,
                mood: selectedMood.rawValue,
                date: entry.date ?? Date(),
                duration: entry.duration
            )
            EntryLearningPipeline.upsertSemanticEntry(entry)
            JournalSpotlightIndexer.shared.upsert(entry: entry)
            DaypartHeroStore().recordPromptResponse(promptID: heroPromptID, wordCount: wordCount(for: trimmed))
            HapticManager.shared.entrySaved()
            cancelNewTextBlock()
            loadBlocks(backfill: false)
            return true
        } catch {
            viewContext.rollback()
            newTextBlockError = String(localized: "Couldn’t save. Try again.")
            return false
        }
    }

    func beginEditingBlock(_ item: JournalBlockTimelineItem) {
        if isComposingTextBlock {
            guard savePendingEditsBeforeExit() else { return }
        }
        editingBlockObjectID = item.id
        editingBlockText = item.text
        blockEditError = nil
        isTextFocused = true
        HapticManager.shared.selectionChanged()
    }

    @discardableResult
    private func finishEditingBlock(_ item: JournalBlockTimelineItem) -> Bool {
        guard let block = block(for: item) else { return false }
        guard JournalBlockTimelineStore.updateTextBlock(block, text: editingBlockText) else {
            blockEditError = String(localized: "Text can’t be empty. Delete it instead?")
            return false
        }
        do {
            try viewContext.save()
            EntryLearningPipeline.upsertSemanticEntry(entry)
            JournalSpotlightIndexer.shared.upsert(entry: entry)
            HapticManager.shared.entrySaved()
        } catch {
            viewContext.rollback()
            return false
        }
        isTextFocused = false
        editingBlockObjectID = nil
        editingBlockText = ""
        blockEditError = nil
        loadBlocks(backfill: false)
        return true
    }
}
