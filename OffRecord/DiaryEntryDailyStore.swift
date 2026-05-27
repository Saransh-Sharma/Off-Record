import CoreData
import Foundation

@MainActor
enum DiaryEntryDailyStore {
    private static let textSeparator = "\n\n"

    @discardableResult
    static func getOrCreateEntry(
        on date: Date = Date(),
        in context: NSManagedObjectContext,
        calendar: Calendar = .current
    ) throws -> DiaryEntry {
        let entries = try entries(on: date, in: context, calendar: calendar)
        if entries.isEmpty {
            return makeEntry(on: date, in: context)
        }
        return try merge(entries, in: context)
    }

    @discardableResult
    static func appendText(
        _ text: String,
        on date: Date = Date(),
        in context: NSManagedObjectContext,
        calendar: Calendar = .current
    ) throws -> DiaryEntry {
        let entry = try getOrCreateEntry(on: date, in: context, calendar: calendar)
        JournalBlockTimelineStore.appendTextBlock(text: text, createdAt: date, to: entry, in: context)
        entry.updatedAt = Date()
        return entry
    }

    @discardableResult
    static func appendText(_ text: String, to entry: DiaryEntry) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if let context = entry.managedObjectContext {
            JournalBlockTimelineStore.appendTextBlock(text: trimmed, createdAt: Date(), to: entry, in: context)
            return true
        }

        let existing = entry.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        entry.text = existing.isEmpty ? trimmed : existing + textSeparator + trimmed
        return true
    }

    @discardableResult
    static func normalizeAllDuplicateDays(
        in context: NSManagedObjectContext,
        calendar: Calendar = .current
    ) throws -> [DiaryEntry] {
        let request: NSFetchRequest<DiaryEntry> = DiaryEntry.fetchRequest()
        request.predicate = NSPredicate(format: "date != nil")
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \DiaryEntry.date, ascending: true),
            NSSortDescriptor(keyPath: \DiaryEntry.updatedAt, ascending: false)
        ]

        let entries = try context.fetch(request).filter { !$0.isDeleted }
        let groupedEntries = Dictionary(grouping: entries) { entry in
            calendar.startOfDay(for: entry.date ?? .distantPast)
        }

        return try groupedEntries.values.compactMap { sameDayEntries in
            guard sameDayEntries.count > 1 else { return nil }
            return try merge(sameDayEntries, in: context)
        }
    }

    @discardableResult
    static func normalizeDuplicateEntries(
        on date: Date,
        in context: NSManagedObjectContext,
        calendar: Calendar = .current
    ) throws -> DiaryEntry? {
        let sameDayEntries = try entries(on: date, in: context, calendar: calendar)
        guard sameDayEntries.count > 1 else { return sameDayEntries.first }
        return try merge(sameDayEntries, in: context)
    }

    static func entries(
        on date: Date,
        in context: NSManagedObjectContext,
        calendar: Calendar = .current
    ) throws -> [DiaryEntry] {
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? date

        let request: NSFetchRequest<DiaryEntry> = DiaryEntry.fetchRequest()
        request.predicate = NSPredicate(format: "date >= %@ AND date < %@", startOfDay as NSDate, endOfDay as NSDate)
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \DiaryEntry.updatedAt, ascending: false),
            NSSortDescriptor(keyPath: \DiaryEntry.date, ascending: false)
        ]

        return try context.fetch(request).filter { !$0.isDeleted }
    }

    private static func makeEntry(on date: Date, in context: NSManagedObjectContext) -> DiaryEntry {
        let entry = DiaryEntry(context: context)
        entry.id = UUID()
        entry.date = date
        entry.createdAt = date
        entry.updatedAt = date
        entry.text = ""
        entry.isStarred = false
        return entry
    }

    @discardableResult
    private static func merge(_ entries: [DiaryEntry], in context: NSManagedObjectContext) throws -> DiaryEntry {
        let activeEntries = entries.filter { !$0.isDeleted }
        guard let primary = activeEntries.max(by: isOlderForPrimarySelection) else {
            throw NSError(domain: "DiaryEntryDailyStore", code: 1)
        }

        if primary.id == nil {
            primary.id = UUID()
        }

        let latestUpdatedAt = activeEntries.compactMap(\.updatedAt).max() ?? primary.updatedAt ?? Date()
        let chronologicalEntries = activeEntries.sorted(by: isEarlierForTextMerge)
        primary.isStarred = activeEntries.contains { $0.isStarred }
        primary.duration = activeEntries.reduce(0) { $0 + max(0, $1.duration) }

        if normalizedAudioFileName(primary).isEmpty,
           let audioFileName = chronologicalEntries.map(normalizedAudioFileName).first(where: { !$0.isEmpty }) {
            primary.audioFileName = audioFileName
        }

        if !hasUsefulMood(primary),
           let mood = chronologicalEntries.map(normalizedMood).first(where: { !$0.isEmpty && $0 != Mood.none.rawValue }) {
            primary.mood = mood
        }

        if primary.createdAt == nil {
            primary.createdAt = chronologicalEntries.compactMap(\.createdAt).min() ?? primary.date
        }
        if primary.date == nil {
            primary.date = chronologicalEntries.compactMap(\.date).max() ?? primary.createdAt ?? Date()
        }

        for entry in activeEntries {
            JournalBlockTimelineStore.backfillBlocksIfNeeded(for: entry, in: context)
        }

        for duplicate in activeEntries where duplicate !== primary {
            let attachments = (duplicate.photos?.allObjects as? [PhotoAttachment]) ?? []
            for attachment in attachments {
                attachment.entry = primary
            }
            let audioAttachments = AudioAttachmentStore.audioAttachments(for: duplicate)
            for attachment in audioAttachments {
                attachment.setValue(primary, forKey: "entry")
            }
            let blocks = (duplicate.value(forKey: "blocks") as? Set<JournalBlock>) ?? []
            for block in blocks {
                block.diaryEntry = primary
            }
            context.delete(duplicate)
        }

        JournalBlockTimelineStore.recomposeLegacyFields(for: primary, touchUpdatedAt: false)
        primary.updatedAt = latestUpdatedAt
        return primary
    }

    private static func isOlderForPrimarySelection(_ lhs: DiaryEntry, _ rhs: DiaryEntry) -> Bool {
        let lhsDate = primarySelectionDate(lhs)
        let rhsDate = primarySelectionDate(rhs)
        if lhsDate != rhsDate { return lhsDate < rhsDate }
        return stableIdentifier(lhs) < stableIdentifier(rhs)
    }

    private static func isEarlierForTextMerge(_ lhs: DiaryEntry, _ rhs: DiaryEntry) -> Bool {
        let lhsDate = lhs.date ?? lhs.createdAt ?? lhs.updatedAt ?? .distantPast
        let rhsDate = rhs.date ?? rhs.createdAt ?? rhs.updatedAt ?? .distantPast
        if lhsDate != rhsDate { return lhsDate < rhsDate }
        return stableIdentifier(lhs) < stableIdentifier(rhs)
    }

    private static func primarySelectionDate(_ entry: DiaryEntry) -> Date {
        entry.updatedAt ?? entry.date ?? entry.createdAt ?? .distantPast
    }

    private static func stableIdentifier(_ entry: DiaryEntry) -> String {
        entry.id?.uuidString ?? entry.objectID.uriRepresentation().absoluteString
    }

    private static func normalizedAudioFileName(_ entry: DiaryEntry) -> String {
        (entry.audioFileName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedMood(_ entry: DiaryEntry) -> String {
        (entry.mood ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func hasUsefulMood(_ entry: DiaryEntry) -> Bool {
        let mood = normalizedMood(entry)
        return !mood.isEmpty && mood != Mood.none.rawValue
    }
}
