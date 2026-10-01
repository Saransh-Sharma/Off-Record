//
//  JournalStore.swift
//  OffRecord
//
//  Model API for journals (Core Data entity `Journal`). An entry belongs to
//  at most one journal; nil means the main journal. Deleting a journal moves
//  its entries back to the main journal. The journals UI builds on this.
//

import CoreData
import Foundation

@MainActor
struct JournalStore {
    /// Longest journal name kept; longer names are cut.
    static let maximumNameLength = 40

    let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    /// Journals in their sort order. Archived journals are left out unless asked for.
    func journals(includingArchived: Bool = false) -> [Journal] {
        let request: NSFetchRequest<Journal> = Journal.fetchRequest()
        if !includingArchived {
            request.predicate = NSPredicate(format: "isArchived == NO")
        }
        request.sortDescriptors = [
            NSSortDescriptor(key: "sortOrder", ascending: true),
            NSSortDescriptor(key: "createdAt", ascending: true)
        ]
        return (try? context.fetch(request)) ?? []
    }

    @discardableResult
    func createJournal(named name: String, iconName: String? = nil, colorName: String? = nil) throws -> Journal {
        let trimmed = Self.normalizedName(name)
        guard !trimmed.isEmpty else { throw JournalOrganizationError.emptyName }
        let journal = Journal(context: context)
        journal.id = UUID()
        journal.name = trimmed
        journal.iconName = iconName
        journal.colorName = colorName
        journal.createdAt = Date()
        journal.isArchived = false
        journal.sortOrder = (journals(includingArchived: true).map(\.sortOrder).max() ?? -1) + 1
        try context.save()
        return journal
    }

    func rename(_ journal: Journal, to name: String) throws {
        let trimmed = Self.normalizedName(name)
        guard !trimmed.isEmpty else { throw JournalOrganizationError.emptyName }
        journal.name = trimmed
        try context.save()
    }

    func setArchived(_ journal: Journal, _ isArchived: Bool) throws {
        journal.isArchived = isArchived
        try context.save()
    }

    /// Deletes the journal. Its entries move back to the main journal.
    func delete(_ journal: Journal) throws {
        context.delete(journal)
        try context.save()
    }

    /// Moves the entry into `journal`, or back to the main journal when nil.
    func assign(_ entry: DiaryEntry, to journal: Journal?) throws {
        entry.journal = journal
        try context.save()
    }

    /// Entries in `journal`, or in the main journal when nil, newest first.
    func entries(in journal: Journal?) -> [DiaryEntry] {
        let request: NSFetchRequest<DiaryEntry> = DiaryEntry.fetchRequest()
        request.predicate = journal.map { NSPredicate(format: "journal == %@", $0) } ?? NSPredicate(format: "journal == nil")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \DiaryEntry.date, ascending: false)]
        return (try? context.fetch(request)) ?? []
    }

    static func normalizedName(_ name: String) -> String {
        String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maximumNameLength))
    }
}
