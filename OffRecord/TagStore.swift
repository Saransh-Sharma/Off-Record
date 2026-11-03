//
//  TagStore.swift
//  OffRecord
//
//  Model API for entry tags (Core Data entity `Tag`, class `JournalTag`).
//  Tags and entries are many-to-many; deleting a tag leaves its entries alone.
//  The tags UI builds on this.
//

import CoreData
import Foundation

enum JournalOrganizationError: Error, Equatable {
    case emptyName
    case duplicateName
}

@MainActor
struct TagStore {
    /// Longest tag name kept; longer names are cut.
    nonisolated static let maximumNameLength = 40

    let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    /// Every tag, sorted by name.
    func allTags() -> [JournalTag] {
        let request: NSFetchRequest<JournalTag> = JournalTag.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true, selector: #selector(NSString.localizedCaseInsensitiveCompare(_:)))]
        return (try? context.fetch(request)) ?? []
    }

    /// The tag with this name, ignoring case and surrounding spaces.
    func tag(named name: String) -> JournalTag? {
        let trimmed = Self.normalizedName(name)
        guard !trimmed.isEmpty else { return nil }
        let request: NSFetchRequest<JournalTag> = JournalTag.fetchRequest()
        request.predicate = NSPredicate(format: "name =[c] %@", trimmed)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    /// Creates a tag, or returns the existing one with the same name.
    @discardableResult
    func createTag(named name: String) throws -> JournalTag {
        let trimmed = Self.normalizedName(name)
        guard !trimmed.isEmpty else { throw JournalOrganizationError.emptyName }
        if let existing = tag(named: trimmed) { return existing }
        let tag = JournalTag(context: context)
        tag.id = UUID()
        tag.name = trimmed
        tag.createdAt = Date()
        try context.save()
        return tag
    }

    func rename(_ tag: JournalTag, to name: String) throws {
        let trimmed = Self.normalizedName(name)
        guard !trimmed.isEmpty else { throw JournalOrganizationError.emptyName }
        if let existing = self.tag(named: trimmed), existing.objectID != tag.objectID {
            throw JournalOrganizationError.duplicateName
        }
        tag.name = trimmed
        try context.save()
    }

    /// Deletes the tag. Its entries stay; they just lose the tag.
    func delete(_ tag: JournalTag) throws {
        context.delete(tag)
        try context.save()
    }

    func assign(_ tag: JournalTag, to entry: DiaryEntry) throws {
        entry.addToTags(tag)
        try context.save()
    }

    func remove(_ tag: JournalTag, from entry: DiaryEntry) throws {
        entry.removeFromTags(tag)
        try context.save()
    }

    /// The entry's tags, sorted by name.
    func tags(for entry: DiaryEntry) -> [JournalTag] {
        ((entry.tags as? Set<JournalTag>) ?? [])
            .filter { !$0.isDeleted }
            .sorted { ($0.name ?? "").localizedCaseInsensitiveCompare($1.name ?? "") == .orderedAscending }
    }

    /// Trims spaces and leading "#", folds inner runs of spaces into one, and cuts long names.
    nonisolated static func normalizedName(_ name: String) -> String {
        var trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasPrefix("#") {
            trimmed = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let words = trimmed.split(whereSeparator: \.isWhitespace)
        return String(words.joined(separator: " ").prefix(maximumNameLength))
            .trimmingCharacters(in: .whitespaces)
    }
}
