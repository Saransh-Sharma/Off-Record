//
//  ImportedTagMapper.swift
//  OffRecord
//
//  Tags from another app's export (Day One and the like) become OffRecord
//  tags on the entry they were imported into. Names are normalized the same
//  way as tags typed in the app, so "#Work", "work", and " Work " are one tag,
//  and tags that already exist are reused. Nothing is saved here: the
//  importer's batch save covers it.
//
//  JournalImportService.commit calls it where the "Wave B: map imported
//  tags" note sits:
//
//      ImportedTagMapper.apply(draft.tags, to: entry, in: context)
//

import CoreData
import Foundation

@MainActor
enum ImportedTagMapper {
    /// Adds each named tag to the entry. Empty and repeated names are skipped.
    /// Returns the tags the entry now has from `names`.
    @discardableResult
    static func apply(_ names: [String], to entry: DiaryEntry, in context: NSManagedObjectContext) -> [JournalTag] {
        let store = TagStore(context: context)
        var seen = Set<String>()
        var applied: [JournalTag] = []
        for name in names {
            let normalized = TagStore.normalizedName(name)
            guard !normalized.isEmpty, seen.insert(normalized.lowercased()).inserted,
                  let tag = try? store.findOrMakeTag(named: normalized) else { continue }
            if !((entry.tags as? Set<JournalTag>) ?? []).contains(tag) {
                entry.addToTags(tag)
            }
            applied.append(tag)
        }
        return applied
    }
}
