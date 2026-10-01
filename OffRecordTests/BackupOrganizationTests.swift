import CoreData
import Foundation
import JournalFoundation
import Testing
@testable import OffRecord

/// JSON and encrypted backups keep each entry's Friday setting, tags, and
/// journal, and still read backups made before those existed.
@MainActor
@Suite(.serialized)
struct BackupOrganizationTests {

    @Test func jsonBackupRoundTripsExclusionTagsAndJournal() throws {
        let source = try makeSourceEntries()
        let url = try BackupService.writeJSONBackup(entries: source.map(ExportableEntry.init(from:)), deviceName: "Test")
        defer { try? FileManager.default.removeItem(at: url) }

        let restore = PersistenceController(inMemory: true).container.viewContext
        let existingFamily = try TagStore(context: restore).createTag(named: "family")

        #expect(try BackupService.shared.importFromJSON(url: url, context: restore) == 2)
        try expectRestored(in: restore, reusing: existingFamily)
    }

    @Test func encryptedBackupRoundTripsExclusionTagsAndJournal() throws {
        let source = try makeSourceEntries()
        let url = try BackupService.writeEncryptedBackup(entries: source.map(ExportableEntry.init(from:)), password: "correct horse", deviceName: "Test")
        defer { try? FileManager.default.removeItem(at: url) }

        let restore = PersistenceController(inMemory: true).container.viewContext
        let existingFamily = try TagStore(context: restore).createTag(named: "family")

        #expect(try BackupService.shared.importEncrypted(url: url, password: "correct horse", context: restore) == 2)
        try expectRestored(in: restore, reusing: existingFamily)
    }

    @Test func includedEntriesWriteNoNewKeys() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let entry = makeEntry("Ordinary Tuesday.", in: context)
        try context.save()

        let data = try JSONEncoder().encode(ExportableEntry(from: entry))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["aiExclusion"] == nil)
        #expect(object["tags"] == nil)
        #expect(object["journal"] == nil)
    }

    @Test func backupFromBeforeTagsAndJournalsStillImports() throws {
        let id = UUID()
        let json = """
        {
          "version": "1.0",
          "exportDate": "2026-05-27T12:00:00Z",
          "deviceName": "Old iPhone",
          "entryCount": 1,
          "entries": [
            {
              "id": "\(id.uuidString)",
              "date": "2026-05-27T09:00:00Z",
              "text": "Walk by the lake.",
              "mood": "calm",
              "isStarred": false,
              "createdAt": "2026-05-27T09:00:00Z",
              "updatedAt": "2026-05-27T09:05:00Z",
              "photos": []
            }
          ]
        }
        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("old-backup-\(UUID().uuidString).json")
        try Data(json.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let restore = PersistenceController(inMemory: true).container.viewContext
        #expect(try BackupService.shared.importFromJSON(url: url, context: restore) == 1)

        let entry = try #require(try restore.fetch(DiaryEntry.fetchRequest()).first)
        #expect(entry.id == id)
        #expect(entry.text == "Walk by the lake.")
        #expect(entry.journalAIExclusion == .included)
        #expect(entry.aiExclusion == nil)
        #expect((entry.tags?.count ?? 0) == 0)
        #expect(entry.journal == nil)
    }

    // MARK: Helpers

    private func makeSourceEntries() throws -> [DiaryEntry] {
        let context = PersistenceController(inMemory: true).container.viewContext
        let keptOut = makeEntry("The custody hearing is next week.", in: context)
        keptOut.journalAIExclusion = .excludedFromAIAndReflection
        let ordinary = makeEntry("Garden tomatoes are finally red.", in: context)
        try context.save()

        let tags = TagStore(context: context)
        try tags.assign(try tags.createTag(named: "Family"), to: keptOut)
        try tags.assign(try tags.createTag(named: "Legal"), to: keptOut)
        let journals = JournalStore(context: context)
        try journals.assign(keptOut, to: try journals.createJournal(named: "Private", iconName: "lock", colorName: "plum"))
        return [keptOut, ordinary]
    }

    private func expectRestored(in context: NSManagedObjectContext, reusing existingFamily: JournalTag) throws {
        let entries = try context.fetch(DiaryEntry.fetchRequest())
        let restoredPrivate = try #require(entries.first { $0.text == "The custody hearing is next week." })
        let restoredOrdinary = try #require(entries.first { $0.text == "Garden tomatoes are finally red." })

        #expect(restoredPrivate.journalAIExclusion == .excludedFromAIAndReflection)
        #expect(TagStore(context: context).tags(for: restoredPrivate).compactMap(\.name).map { $0.lowercased() } == ["family", "legal"])
        #expect(TagStore(context: context).tags(for: restoredPrivate).contains { $0.objectID == existingFamily.objectID })
        #expect(TagStore(context: context).allTags().count == 2)
        #expect(restoredPrivate.journal?.name == "Private")
        #expect(restoredPrivate.journal?.iconName == "lock")
        #expect(restoredPrivate.journal?.colorName == "plum")

        #expect(restoredOrdinary.journalAIExclusion == .included)
        #expect((restoredOrdinary.tags?.count ?? 0) == 0)
        #expect(restoredOrdinary.journal == nil)
    }

    private func makeEntry(_ text: String, in context: NSManagedObjectContext) -> DiaryEntry {
        let entry = DiaryEntry(context: context)
        let now = Date()
        entry.id = UUID()
        entry.date = now
        entry.createdAt = now
        entry.updatedAt = now
        entry.text = text
        JournalBlockTimelineStore.backfillBlocksIfNeeded(for: entry, in: context)
        return entry
    }
}
