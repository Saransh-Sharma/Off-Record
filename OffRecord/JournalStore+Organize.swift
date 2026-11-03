//
//  JournalStore+Organize.swift
//  OffRecord
//
//  Multiple journals on top of JournalStore. A day's identity is (day,
//  journal), with nil as the main journal, so moving an entry or deleting a
//  journal re-merges only the affected days in the journal they land in.
//  Record and Write default to the last journal the person picked, or the
//  main journal when that one is gone or archived. Journal names never leave
//  the app: widgets, Spotlight, Siri, and notifications don't show them.
//

import CoreData
import Foundation

/// Which journals a list shows.
enum JournalScope: Hashable, Sendable {
    case all
    /// Entries with no journal.
    case main
    case journal(UUID)

    init(journal: Journal?) {
        if let id = journal?.id {
            self = .journal(id)
        } else {
            self = .main
        }
    }

    func includes(_ entry: DiaryEntry) -> Bool {
        switch self {
        case .all: return true
        case .main: return entry.journal == nil
        case .journal(let id): return entry.journal?.id == id
        }
    }

    func filter(_ entries: [DiaryEntry]) -> [DiaryEntry] {
        self == .all ? entries : entries.filter(includes)
    }

    /// A stable string for cache keys.
    var signature: String {
        switch self {
        case .all: return "all"
        case .main: return "main"
        case .journal(let id): return id.uuidString
        }
    }
}

enum JournalNames {
    /// The journal every entry starts in. It has no name of its own.
    static var main: String {
        String(localized: "Main", comment: "Name of the main journal, the one entries go to unless another journal is picked")
    }

    static var all: String {
        String(localized: "All Journals", comment: "Picker option that shows entries from every journal")
    }

    static func displayName(for journal: Journal?) -> String {
        guard let journal else { return main }
        let name = (journal.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? main : name
    }

    static func displayName(for scope: JournalScope, journals: [Journal]) -> String {
        switch scope {
        case .all: return all
        case .main: return main
        case .journal(let id): return displayName(for: journals.first { $0.id == id })
        }
    }

    static let defaultIconName = "book.closed"
}

/// What happens to a journal's entries when the journal is deleted.
enum JournalDeletionChoice: Equatable {
    /// Entries join the main journal; days that already have a main entry merge into it.
    case moveEntriesToMain
    /// Entries, with their recordings and photos, are deleted.
    case deleteEntries
}

/// The index and file work that follows a journal change. Apply it after the save succeeds.
struct JournalChangeResult {
    var updatedEntries: [DiaryEntry] = []
    var deletedEntryIDs: [UUID] = []
    var fileURLsToRemove: [URL] = []
}

extension JournalStore {
    func journal(withID id: UUID?) -> Journal? {
        guard let id else { return nil }
        let request: NSFetchRequest<Journal> = Journal.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first { !$0.isDeleted }
    }

    /// True when another journal, or the main journal, already has this name (ignoring case).
    func isNameTaken(_ name: String, excluding journal: Journal? = nil) -> Bool {
        let trimmed = Self.normalizedName(name)
        guard !trimmed.isEmpty else { return false }
        if trimmed.compare(JournalNames.main, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
            return true
        }
        return journals(includingArchived: true).contains { other in
            other.objectID != journal?.objectID
                && (other.name ?? "").compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }

    /// Moves the entry into `journal` (nil is the main journal). When that journal
    /// already has an entry for the day, the two merge and the moved entry survives.
    @discardableResult
    func move(_ entry: DiaryEntry, to journal: Journal?, calendar: Calendar = .current) throws -> JournalChangeResult {
        guard entry.journal?.objectID != journal?.objectID else {
            return JournalChangeResult(updatedEntries: [entry])
        }
        entry.journal = journal
        // The most recently updated entry is the one a merge keeps.
        entry.updatedAt = Date()
        try context.save()

        var result = JournalChangeResult()
        if let date = entry.date {
            try mergeDay(date, journal: journal, calendar: calendar, into: &result)
        } else {
            result.updatedEntries.append(entry)
        }
        if context.hasChanges {
            try context.save()
        }
        return result
    }

    /// Deletes the journal. Its entries either join the main journal, merging
    /// with any main entry on the same day, or are deleted with their files.
    @discardableResult
    func delete(_ journal: Journal, choice: JournalDeletionChoice, calendar: Calendar = .current) throws -> JournalChangeResult {
        var result = JournalChangeResult()
        let journalEntries = entries(in: journal)
        let deletedJournalID = journal.id

        switch choice {
        case .deleteEntries:
            for entry in journalEntries {
                let plan = JournalBlockTimelineStore.prepareDeleteWholeDay(entry, in: context)
                result.fileURLsToRemove += plan.fileURLsToRemoveAfterSave
                if let id = plan.entryID { result.deletedEntryIDs.append(id) }
            }
            context.delete(journal)
            try context.save()

        case .moveEntriesToMain:
            var days = Set<Date>()
            for entry in journalEntries {
                entry.journal = nil
                if let date = entry.date { days.insert(calendar.startOfDay(for: date)) }
            }
            context.delete(journal)
            try context.save()
            for day in days.sorted() {
                try mergeDay(day, journal: nil, calendar: calendar, into: &result)
            }
            if context.hasChanges {
                try context.save()
            }
        }

        if let deletedJournalID, JournalSelectionPreference.lastUsedJournalID == deletedJournalID {
            JournalSelectionPreference.lastUsedJournalID = nil
        }
        return result
    }

    private func mergeDay(_ date: Date, journal: Journal?, calendar: Calendar, into result: inout JournalChangeResult) throws {
        let sameDay = try DiaryEntryDailyStore.entries(on: date, journal: journal, in: context, calendar: calendar)
        let survivor = try DiaryEntryDailyStore.normalizeDuplicateEntries(on: date, journal: journal, in: context, calendar: calendar)
        result.deletedEntryIDs += sameDay.filter(\.isDeleted).compactMap(\.id)
        if let survivor, !survivor.isDeleted {
            result.updatedEntries.append(survivor)
        }
    }
}

@MainActor
enum JournalChangeApplier {
    /// Brings the search index, Spotlight, and files in line after a saved journal change.
    static func apply(_ result: JournalChangeResult) {
        for url in result.fileURLsToRemove {
            try? FileManager.default.removeItem(at: url)
        }
        for id in result.deletedEntryIDs {
            SemanticMemoryIndexController.shared.deleteEntry(id: id)
            JournalSpotlightIndexer.shared.delete(entryID: id)
        }
        for entry in result.updatedEntries where !entry.isDeleted {
            EntryLearningPipeline.upsertSemanticEntry(entry)
            JournalSpotlightIndexer.shared.upsert(entry: entry)
        }
    }
}

/// The journal Record and Write use: the last one the person picked, or the main journal.
enum JournalSelectionPreference {
    static let defaultsKey = "offrecord.journals.lastUsedID"

    /// Stored on this iPhone only, and only as an ID.
    static var lastUsedJournalID: UUID? {
        get { UserDefaults.standard.string(forKey: defaultsKey).flatMap(UUID.init(uuidString:)) }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.uuidString, forKey: defaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: defaultsKey)
            }
        }
    }

    /// The journal to use when nothing else is open: the last one picked if it still
    /// exists and isn't archived, otherwise nil (the main journal).
    @MainActor
    static func defaultJournal(in context: NSManagedObjectContext) -> Journal? {
        usableJournal(withID: lastUsedJournalID, in: context)
    }

    /// The journal with this ID when entries can go into it, otherwise nil (the main journal).
    @MainActor
    static func usableJournal(withID id: UUID?, in context: NSManagedObjectContext) -> Journal? {
        guard let journal = JournalStore(context: context).journal(withID: id), !journal.isArchived else { return nil }
        return journal
    }

    static func remember(_ journal: Journal?) {
        lastUsedJournalID = journal?.id
    }
}
