import CoreData
import Foundation

enum JournalBlockKind: String, CaseIterable {
    case text
    case audio
    case mood
    case photo
}

extension JournalBlock {
    var blockID: UUID {
        get {
            if let id = value(forKey: "id") as? UUID {
                return id
            }
            let id = UUID()
            setValue(id, forKey: "id")
            return id
        }
        set { setValue(newValue, forKey: "id") }
    }

    var blockKind: JournalBlockKind? {
        get { JournalBlockKind(rawValue: value(forKey: "kind") as? String ?? "") }
        set { setValue(newValue?.rawValue, forKey: "kind") }
    }

    var blockCreatedAt: Date {
        get { value(forKey: "createdAt") as? Date ?? .distantPast }
        set { setValue(newValue, forKey: "createdAt") }
    }

    var blockUpdatedAt: Date {
        get { value(forKey: "updatedAt") as? Date ?? blockCreatedAt }
        set { setValue(newValue, forKey: "updatedAt") }
    }

    var blockSortOrder: Int32 {
        get { value(forKey: "sortOrder") as? Int32 ?? 0 }
        set { setValue(newValue, forKey: "sortOrder") }
    }

    var textValue: String {
        get { value(forKey: "text") as? String ?? "" }
        set { setValue(newValue, forKey: "text") }
    }

    var moodValue: String {
        get { value(forKey: "mood") as? String ?? "" }
        set { setValue(newValue, forKey: "mood") }
    }

    var durationValue: Double {
        get { value(forKey: "duration") as? Double ?? 0 }
        set { setValue(newValue, forKey: "duration") }
    }

    var sourceCaptureIDValue: UUID? {
        get { value(forKey: "sourceCaptureID") as? UUID }
        set { setValue(newValue, forKey: "sourceCaptureID") }
    }

    var audioAttachmentIDValue: UUID? {
        get { value(forKey: "audioAttachmentID") as? UUID }
        set { setValue(newValue, forKey: "audioAttachmentID") }
    }

    var photoAttachmentIDValue: UUID? {
        get { value(forKey: "photoAttachmentID") as? UUID }
        set { setValue(newValue, forKey: "photoAttachmentID") }
    }

    var diaryEntry: DiaryEntry? {
        get { value(forKey: "entry") as? DiaryEntry }
        set { setValue(newValue, forKey: "entry") }
    }
}

enum JournalBlockTimelinePresentation {
    static func label(for date: Date, calendar: Calendar = .current) -> String {
        "\(daypart(for: date, calendar: calendar)) · \(date.formatted(date: .omitted, time: .shortened))"
    }

    static func daypart(for date: Date, calendar: Calendar = .current) -> String {
        switch calendar.component(.hour, from: date) {
        case 0..<5: return "Late night"
        case 5..<8: return "Early morning"
        case 8..<12: return "Morning"
        case 12..<17: return "Afternoon"
        case 17..<21: return "Evening"
        default: return "Night"
        }
    }
}

struct JournalBlockDeletionPlan {
    let fileURLsToRemoveAfterSave: [URL]
}

struct JournalDayDeletionPlan {
    let entryID: UUID?
    let fileURLsToRemoveAfterSave: [URL]
}

@MainActor
enum JournalBlockTimelineStore {
    static func blocks(for entry: DiaryEntry) -> [JournalBlock] {
        let blocks = ((entry.value(forKey: "blocks") as? Set<JournalBlock>) ?? []).filter { !$0.isDeleted }
        return blocks.sorted(by: isEarlierBlock)
    }

    @discardableResult
    static func appendTextBlock(
        text: String,
        createdAt: Date,
        on date: Date? = nil,
        in context: NSManagedObjectContext,
        sourceCaptureID: UUID? = nil
    ) throws -> DiaryEntry {
        let entry = try DiaryEntryDailyStore.getOrCreateEntry(on: date ?? createdAt, in: context)
        appendTextBlock(text: text, createdAt: createdAt, to: entry, in: context, sourceCaptureID: sourceCaptureID)
        return entry
    }

    @discardableResult
    static func appendTextBlock(
        text: String,
        createdAt: Date,
        to entry: DiaryEntry,
        in context: NSManagedObjectContext,
        sourceCaptureID: UUID? = nil
    ) -> JournalBlock? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let block = makeBlock(kind: .text, createdAt: createdAt, entry: entry, context: context)
        block.textValue = trimmed
        block.sourceCaptureIDValue = sourceCaptureID
        recomposeLegacyFields(for: entry, touchUpdatedAt: true)
        return block
    }

    @discardableResult
    static func appendMoodBlock(
        mood: Mood,
        createdAt: Date,
        on date: Date? = nil,
        in context: NSManagedObjectContext
    ) throws -> DiaryEntry {
        let entry = try DiaryEntryDailyStore.getOrCreateEntry(on: date ?? createdAt, in: context)
        appendMoodBlock(mood: mood, createdAt: createdAt, to: entry, in: context)
        return entry
    }

    @discardableResult
    static func appendMoodBlock(
        mood: Mood,
        createdAt: Date,
        to entry: DiaryEntry,
        in context: NSManagedObjectContext
    ) -> JournalBlock? {
        guard mood != .none else { return nil }
        let block = makeBlock(kind: .mood, createdAt: createdAt, entry: entry, context: context)
        block.moodValue = mood.rawValue
        recomposeLegacyFields(for: entry, touchUpdatedAt: true)
        return block
    }

    @discardableResult
    static func appendAudioBlock(
        attachment: NSManagedObject,
        createdAt: Date,
        sourceCaptureID: UUID?,
        to entry: DiaryEntry,
        in context: NSManagedObjectContext
    ) -> JournalBlock? {
        let attachmentID = attachment.value(forKey: "id") as? UUID
        if let existing = block(audioAttachmentID: attachmentID, sourceCaptureID: sourceCaptureID, in: entry) {
            return existing
        }

        let block = makeBlock(kind: .audio, createdAt: createdAt, entry: entry, context: context)
        block.audioAttachmentIDValue = attachmentID
        block.sourceCaptureIDValue = sourceCaptureID
        block.durationValue = attachment.value(forKey: "duration") as? Double ?? 0
        recomposeLegacyFields(for: entry, touchUpdatedAt: true)
        return block
    }

    @discardableResult
    static func appendPhotoBlock(
        attachment: PhotoAttachment,
        createdAt: Date,
        to entry: DiaryEntry,
        in context: NSManagedObjectContext
    ) -> JournalBlock? {
        let attachmentID = attachment.id
        if let existing = blocks(for: entry).first(where: { $0.photoAttachmentIDValue == attachmentID }) {
            return existing
        }

        let block = makeBlock(kind: .photo, createdAt: createdAt, entry: entry, context: context)
        block.photoAttachmentIDValue = attachmentID
        recomposeLegacyFields(for: entry, touchUpdatedAt: true)
        return block
    }

    static func updateTextBlock(_ block: JournalBlock, text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        block.textValue = trimmed
        block.blockUpdatedAt = Date()
        if let entry = block.diaryEntry {
            recomposeLegacyFields(for: entry, touchUpdatedAt: true)
        }
        return true
    }

    static func deleteBlock(_ block: JournalBlock, in context: NSManagedObjectContext) -> JournalBlockDeletionPlan {
        var fileURLs: [URL] = []
        guard let entry = block.diaryEntry else {
            context.delete(block)
            return JournalBlockDeletionPlan(fileURLsToRemoveAfterSave: fileURLs)
        }

        switch block.blockKind {
        case .audio:
            if let id = block.audioAttachmentIDValue,
               let attachment = AudioAttachmentStore.audioAttachment(id: id, in: context) {
                if let url = AudioAttachmentStore.audioURL(for: attachment) {
                    fileURLs.append(url)
                }
                context.delete(attachment)
            }
        case .photo:
            if let id = block.photoAttachmentIDValue,
               let attachment = PhotoStorageManager.shared.attachments(for: entry).first(where: { $0.id == id }) {
                PhotoStorageManager.shared.removePhoto(attachment, from: entry, in: context)
            }
        default:
            break
        }

        context.delete(block)
        recomposeLegacyFields(for: entry, touchUpdatedAt: true)
        return JournalBlockDeletionPlan(fileURLsToRemoveAfterSave: fileURLs)
    }

    static func prepareDeleteWholeDay(_ entry: DiaryEntry, in context: NSManagedObjectContext) -> JournalDayDeletionPlan {
        let fileURLs = AudioAttachmentStore.audioURLs(for: entry)
        let plan = JournalDayDeletionPlan(entryID: entry.id, fileURLsToRemoveAfterSave: fileURLs)
        context.delete(entry)
        return plan
    }

    @discardableResult
    static func backfillBlocksIfNeeded(for entry: DiaryEntry, in context: NSManagedObjectContext) -> Bool {
        var changed = false
        let originalUpdatedAt = entry.updatedAt
        let existing = blocks(for: entry)
        let legacyText = entry.text ?? ""
        let legacyMood = (entry.value(forKey: "mood") as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let legacyAudioFileName = (entry.audioFileName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let legacyDuration = entry.duration

        if !(legacyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty),
           !existing.contains(where: { $0.blockKind == .text }) {
            let block = makeBlock(kind: .text, createdAt: entry.createdAt ?? entry.date ?? Date(), entry: entry, context: context)
            block.textValue = legacyText.trimmingCharacters(in: .whitespacesAndNewlines)
            changed = true
        }

        if !legacyMood.isEmpty,
           legacyMood != Mood.none.rawValue,
           !existing.contains(where: { $0.blockKind == .mood }) {
            let mood = Mood(rawValue: legacyMood) ?? .none
            if mood != .none {
                let block = makeBlock(kind: .mood, createdAt: entry.updatedAt ?? entry.date ?? Date(), entry: entry, context: context)
                block.moodValue = mood.rawValue
                changed = true
            }
        }

        let audioBlocks = blocks(for: entry).filter { $0.blockKind == .audio }
        for attachment in AudioAttachmentStore.audioAttachments(for: entry) {
            let attachmentID = attachment.value(forKey: "id") as? UUID
            let sourceCaptureID = attachment.value(forKey: "sourceCaptureID") as? UUID
            let hasBlock = audioBlocks.contains {
                $0.audioAttachmentIDValue == attachmentID
                    || (sourceCaptureID != nil && $0.sourceCaptureIDValue == sourceCaptureID)
            }
            guard !hasBlock else { continue }
            let block = makeBlock(kind: .audio, createdAt: attachment.value(forKey: "createdAt") as? Date ?? entry.date ?? Date(), entry: entry, context: context)
            block.audioAttachmentIDValue = attachmentID
            block.sourceCaptureIDValue = sourceCaptureID
            block.durationValue = attachment.value(forKey: "duration") as? Double ?? 0
            changed = true
        }

        if !legacyAudioFileName.isEmpty,
           AudioAttachmentStore.audioAttachments(for: entry).isEmpty,
           !blocks(for: entry).contains(where: {
               $0.blockKind == .audio && $0.textValue == legacyAudioFileName
        }) {
            let block = makeBlock(kind: .audio, createdAt: entry.createdAt ?? entry.date ?? Date(), entry: entry, context: context)
            block.textValue = legacyAudioFileName
            block.durationValue = legacyDuration
            changed = true
        }

        let photoBlocks = blocks(for: entry).filter { $0.blockKind == .photo }
        for attachment in PhotoStorageManager.shared.attachments(for: entry) {
            let attachmentID = attachment.id
            guard !photoBlocks.contains(where: { $0.photoAttachmentIDValue == attachmentID }) else { continue }
            let block = makeBlock(kind: .photo, createdAt: attachment.createdAt ?? entry.date ?? Date(), entry: entry, context: context)
            block.photoAttachmentIDValue = attachmentID
            changed = true
        }

        if changed {
            recomposeLegacyFields(for: entry, touchUpdatedAt: false)
            entry.updatedAt = originalUpdatedAt
        }
        return changed
    }

    static func recomposeLegacyFields(for entry: DiaryEntry, touchUpdatedAt: Bool = true) {
        let sortedBlocks = blocks(for: entry)
        let textBlocks = sortedBlocks.filter { $0.blockKind == .text }
        let composedText = textBlocks.compactMap { block -> String? in
            let text = block.textValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return text
        }.joined(separator: "\n\n")
        entry.text = composedText

        let latestMood = sortedBlocks.reversed().compactMap { block -> String? in
            guard block.blockKind == .mood else { return nil }
            let mood = block.moodValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return mood.isEmpty || mood == Mood.none.rawValue ? nil : mood
        }.first
        entry.setValue(latestMood, forKey: "mood")

        let audioAttachments = AudioAttachmentStore.audioAttachments(for: entry)
        if audioAttachments.isEmpty {
            let audioBlocks = sortedBlocks.filter { $0.blockKind == .audio }
            entry.duration = audioBlocks.reduce(0) { $0 + max(0, $1.durationValue) }
            entry.audioFileName = audioBlocks.map { $0.textValue.trimmingCharacters(in: .whitespacesAndNewlines) }.first(where: { !$0.isEmpty })
        } else {
            entry.duration = audioAttachments.reduce(0) {
                $0 + max(0, $1.value(forKey: "duration") as? Double ?? 0)
            }
            entry.audioFileName = audioAttachments.first?.value(forKey: "fileName") as? String
        }
        if touchUpdatedAt {
            entry.updatedAt = Date()
        }
    }

    private static func makeBlock(
        kind: JournalBlockKind,
        createdAt: Date,
        entry: DiaryEntry,
        context: NSManagedObjectContext
    ) -> JournalBlock {
        let block = NSEntityDescription.insertNewObject(forEntityName: "JournalBlock", into: context) as! JournalBlock
        block.blockID = UUID()
        block.blockKind = kind
        block.blockCreatedAt = createdAt
        block.blockUpdatedAt = Date()
        block.blockSortOrder = nextSortOrder(for: entry)
        block.diaryEntry = entry
        return block
    }

    private static func nextSortOrder(for entry: DiaryEntry) -> Int32 {
        let maxOrder = blocks(for: entry)
            .map(\.blockSortOrder)
            .max() ?? -1
        return maxOrder + 1
    }

    private static func block(audioAttachmentID: UUID?, sourceCaptureID: UUID?, in entry: DiaryEntry) -> JournalBlock? {
        blocks(for: entry).first { block in
            guard block.blockKind == .audio else { return false }
            if let audioAttachmentID, block.audioAttachmentIDValue == audioAttachmentID {
                return true
            }
            if let sourceCaptureID, block.sourceCaptureIDValue == sourceCaptureID {
                return true
            }
            return false
        }
    }

    private static func isEarlierBlock(_ lhs: JournalBlock, _ rhs: JournalBlock) -> Bool {
        let lhsDate = lhs.blockCreatedAt
        let rhsDate = rhs.blockCreatedAt
        if lhsDate != rhsDate { return lhsDate < rhsDate }

        let lhsOrder = lhs.blockSortOrder
        let rhsOrder = rhs.blockSortOrder
        if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }

        let lhsID = lhs.blockID.uuidString
        let rhsID = rhs.blockID.uuidString
        return lhsID < rhsID
    }
}
