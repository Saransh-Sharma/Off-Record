//
//  EntryDetailView+Blocks.swift
//  OffRecord
//
//  Reading the entry's journal blocks from the store and turning them into
//  timeline items, with each recording resolved to its file.
//

import CoreData

extension EntryDetailView {
    func loadBlocks(backfill: Bool) {
        if backfill, JournalBlockTimelineStore.backfillBlocksIfNeeded(for: entry, in: viewContext) {
            try? viewContext.save()
        }
        journalBlocks = JournalBlockTimelineStore.blocks(for: entry)
        timelineItems = makeTimelineItems(from: journalBlocks)
        text = entry.text ?? ""
        selectedMood = Mood(rawValue: entry.value(forKey: "mood") as? String ?? "") ?? .none
    }

    private func makeTimelineItems(from blocks: [JournalBlock]) -> [JournalBlockTimelineItem] {
        let audioAttachments = Dictionary(uniqueKeysWithValues: AudioAttachmentStore.audioAttachments(for: entry).compactMap { attachment -> (UUID, NSManagedObject)? in
            guard let id = attachment.value(forKey: "id") as? UUID else { return nil }
            return (id, attachment)
        })

        return blocks.compactMap { block in
            guard let kind = block.blockKind else { return nil }
            let createdAt = block.blockCreatedAt == .distantPast ? (entry.date ?? Date()) : block.blockCreatedAt
            let timestamp = JournalBlockTimelinePresentation.label(for: createdAt)
            let mood = Mood(rawValue: block.moodValue) ?? .none
            var audioURL: URL?
            if let id = block.audioAttachmentIDValue,
               let attachment = audioAttachments[id] {
                audioURL = AudioAttachmentStore.audioURL(for: attachment)
            } else if kind == .audio {
                let legacyFileName = block.textValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !legacyFileName.isEmpty {
                    audioURL = try? AudioAttachmentStore.destinationURL(for: legacyFileName)
                }
            }

            return JournalBlockTimelineItem(
                id: block.objectID,
                blockID: block.blockID,
                kind: kind,
                createdAt: createdAt,
                sourceCaptureID: block.sourceCaptureIDValue,
                timestamp: timestamp,
                text: block.textValue,
                mood: mood,
                duration: block.durationValue,
                audioURL: audioURL,
                audioExists: audioURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false,
                photoAttachmentID: block.photoAttachmentIDValue
            )
        }
    }

    func block(for item: JournalBlockTimelineItem) -> JournalBlock? {
        try? viewContext.existingObject(with: item.id) as? JournalBlock
    }

    private func blockKind(_ block: NSManagedObject) -> JournalBlockKind? {
        JournalBlockKind(rawValue: block.value(forKey: "kind") as? String ?? "")
    }

    private func audioURL(for block: NSManagedObject) -> URL? {
        if let id = block.value(forKey: "audioAttachmentID") as? UUID,
           let attachment = AudioAttachmentStore.audioAttachment(id: id, in: viewContext) {
            return AudioAttachmentStore.audioURL(for: attachment)
        }
        if let legacyFileName = (block.value(forKey: "text") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !legacyFileName.isEmpty {
            return try? AudioAttachmentStore.destinationURL(for: legacyFileName)
        }
        return nil
    }
}
