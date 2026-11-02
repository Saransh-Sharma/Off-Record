//
//  TagStore+Organize.swift
//  OffRecord
//
//  Tags on top of TagStore: adding and removing them on an entry, suggestions
//  while typing, renaming (which merges into a tag that already has the new
//  name), merging, deleting, and the tag part of Timeline search. Names are
//  trimmed and unique ignoring case. Tag names stay in the app: widgets,
//  Spotlight, Siri, and notifications never show them.
//

import CoreData
import Foundation

extension TagStore {
    /// The tag with this name, or a new one, without saving. For batched work such as imports.
    func findOrMakeTag(named name: String) throws -> JournalTag {
        let trimmed = Self.normalizedName(name)
        guard !trimmed.isEmpty else { throw JournalOrganizationError.emptyName }
        if let existing = tag(named: trimmed) { return existing }
        let tag = JournalTag(context: context)
        tag.id = UUID()
        tag.name = trimmed
        tag.createdAt = Date()
        return tag
    }

    /// Tags the entry, reusing a tag with the same name when there is one.
    @discardableResult
    func addTag(named name: String, to entry: DiaryEntry) throws -> JournalTag {
        let tag = try findOrMakeTag(named: name)
        if !hasTag(tag, entry) {
            entry.addToTags(tag)
            Self.touch([entry])
        }
        try context.save()
        return tag
    }

    func removeTag(_ tag: JournalTag, from entry: DiaryEntry) throws {
        guard hasTag(tag, entry) else { return }
        entry.removeFromTags(tag)
        Self.touch([entry])
        try context.save()
    }

    /// Renames the tag. When another tag already has that name, this one merges into it,
    /// and the surviving tag is returned.
    @discardableResult
    func renameOrMerge(_ tag: JournalTag, to name: String) throws -> JournalTag {
        let trimmed = Self.normalizedName(name)
        guard !trimmed.isEmpty else { throw JournalOrganizationError.emptyName }
        if let existing = self.tag(named: trimmed), existing.objectID != tag.objectID {
            try merge(tag, into: existing)
            return existing
        }
        tag.name = trimmed
        Self.touch(entries(taggedWith: tag))
        try context.save()
        return tag
    }

    /// Every entry tagged `source` gets `target` instead, and `source` is deleted.
    func merge(_ source: JournalTag, into target: JournalTag) throws {
        guard source.objectID != target.objectID else { return }
        let moved = entries(taggedWith: source)
        for entry in moved {
            entry.addToTags(target)
            entry.removeFromTags(source)
        }
        Self.touch(moved)
        context.delete(source)
        try context.save()
    }

    /// Deletes the tag. Its entries stay and lose only the tag.
    func deleteTag(_ tag: JournalTag) throws {
        Self.touch(entries(taggedWith: tag))
        context.delete(tag)
        try context.save()
    }

    /// Existing tags for a half-typed name: names that start with it first, then names
    /// that contain it. Tags in `excluding` (usually the entry's own) are left out.
    func suggestions(for query: String, excluding excluded: Set<NSManagedObjectID> = [], limit: Int = 6) -> [JournalTag] {
        let needle = Self.normalizedName(query)
        let candidates = allTags().filter { !$0.isDeleted && !excluded.contains($0.objectID) }
        guard !needle.isEmpty else { return Array(candidates.prefix(limit)) }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let prefix = candidates.filter { ($0.name ?? "").range(of: needle, options: options.union(.anchored)) != nil }
        let contains = candidates.filter { tag in
            !prefix.contains(tag) && (tag.name ?? "").range(of: needle, options: options) != nil
        }
        return Array((prefix + contains).prefix(limit))
    }

    /// Started entries with the tag.
    func entryCount(for tag: JournalTag) -> Int {
        entries(taggedWith: tag).filter(\.isStartedEntry).count
    }

    func entries(taggedWith tag: JournalTag) -> [DiaryEntry] {
        ((tag.entries as? Set<DiaryEntry>) ?? []).filter { !$0.isDeleted }
    }

    private func hasTag(_ tag: JournalTag, _ entry: DiaryEntry) -> Bool {
        ((entry.tags as? Set<JournalTag>) ?? []).contains(tag)
    }

    /// Timeline and other lists refresh on `updatedAt`, so a tag change on an entry touches it.
    private static func touch(_ entries: [DiaryEntry]) {
        let now = Date()
        for entry in entries {
            entry.updatedAt = now
        }
    }
}

/// The tag part of Timeline search and filters.
enum TagSearch {
    /// "#work" searches tags only and gives "work"; nil for any other query.
    static func hashtagQuery(_ query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("#") else { return nil }
        return TagStore.normalizedName(trimmed)
    }

    static func names(of entry: DiaryEntry) -> [String] {
        ((entry.tags as? Set<JournalTag>) ?? []).filter { !$0.isDeleted }.compactMap(\.name)
    }

    /// For a "#" query: a tag that starts with what was typed ("#wor" finds Work).
    /// "#" alone matches any tagged entry.
    static func entry(_ entry: DiaryEntry, matchesHashtag query: String) -> Bool {
        let names = names(of: entry)
        guard !query.isEmpty else { return !names.isEmpty }
        return names.contains { $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil }
    }

    /// For a plain query: a tag with exactly that name.
    static func entry(_ entry: DiaryEntry, hasTagNamed query: String) -> Bool {
        let needle = TagStore.normalizedName(query)
        guard !needle.isEmpty else { return false }
        return names(of: entry).contains { $0.compare(needle, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
    }

    static func entry(_ entry: DiaryEntry, hasTagWithID id: UUID) -> Bool {
        ((entry.tags as? Set<JournalTag>) ?? []).contains { !$0.isDeleted && $0.id == id }
    }
}
