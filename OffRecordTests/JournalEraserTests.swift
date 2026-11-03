import CoreData
import Foundation
import Testing
@testable import OffRecord

/// Erase All Data, against an in-memory store and temporary folders.
@MainActor
@Suite(.serialized)
struct JournalEraserTests {

    @Test func eraseStoreDeletesEveryObject() async throws {
        let container = PersistenceController(inMemory: true).container
        let context = container.viewContext
        let entry = DiaryEntry(context: context)
        entry.id = UUID()
        entry.date = Date()
        entry.updatedAt = Date()
        entry.text = "Dinner with Maya by the lake."
        JournalBlockTimelineStore.backfillBlocksIfNeeded(for: entry, in: context)
        let photo = PhotoAttachment(context: context)
        photo.id = UUID()
        photo.imageData = Data([1, 2, 3])
        photo.entry = entry
        AudioAttachmentStore.attachAudio(
            fileName: "erase-test.m4a",
            duration: 3,
            createdAt: Date(),
            sourceCaptureID: UUID(),
            byteCount: 3,
            codec: "aac-lc",
            to: entry,
            in: context
        )
        let state = AIState(context: context)
        state.id = UUID()
        state.type = "weekly_reflection_reports"
        state.payload = Data("{}".utf8)
        let receipt = WatchImportReceipt(context: context)
        receipt.captureID = UUID()
        try context.save()
        try TagStore(context: context).assign(try TagStore(context: context).createTag(named: "Family"), to: entry)
        try JournalStore(context: context).assign(entry, to: try JournalStore(context: context).createJournal(named: "Trips"))
        // Many objects, to cross a batch boundary.
        for index in 0..<(JournalEraser.batchSize + 5) {
            let extra = DiaryEntry(context: context)
            extra.id = UUID()
            extra.text = "Entry \(index)"
        }
        try context.save()
        #expect(try totalObjectCount(container) > JournalEraser.batchSize)

        let eraser = JournalEraser(container: container, locations: try temporaryLocations().locations, defaultsDomain: nil)
        let deleted = try await eraser.eraseStore()

        #expect(deleted > JournalEraser.batchSize)
        #expect(try totalObjectCount(container) == 0)
        // The view context sees the deletes too.
        #expect(try context.count(for: DiaryEntry.fetchRequest()) == 0)
    }

    @Test func entriesAreDeletedFirst() {
        let model = PersistenceController(inMemory: true).container.managedObjectModel
        let order = JournalEraser.deletionOrder(model)

        #expect(order.first == "DiaryEntry")
        #expect(Set(order) == Set(model.entities.compactMap(\.name)))
        #expect(order.contains("Tag"))
        #expect(order.contains("Journal"))
        #expect(order.contains("AIState"))
    }

    @Test func eraseFilesRemovesJournalFoldersTemporaryFilesAndTheWidgetSnapshot() throws {
        let (locations, root) = try temporaryLocations()
        defer { try? FileManager.default.removeItem(at: root) }
        let files = [
            locations.applicationSupport.appendingPathComponent("Recordings/one.m4a"),
            locations.applicationSupport.appendingPathComponent("Photos/one.jpg"),
            locations.applicationSupport.appendingPathComponent("FridayLocal/friday-profile.json"),
            locations.applicationSupport.appendingPathComponent("FridayLocal/friday-conversation.json"),
            locations.temporary.appendingPathComponent("offrecord_backup_2026-05-27.json"),
            locations.temporary.appendingPathComponent("watch-session-1-capture.m4a"),
        ]
        let kept = locations.applicationSupport.appendingPathComponent("Unrelated/keep.txt")
        for url in files + [kept, try #require(locations.widgetSnapshot)] {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("x".utf8).write(to: url)
        }

        JournalEraser(container: PersistenceController(inMemory: true).container, locations: locations, defaultsDomain: nil).eraseFiles()

        for url in files {
            #expect(!FileManager.default.fileExists(atPath: url.path), "\(url.lastPathComponent) should be gone")
        }
        for folder in locations.journalFolders {
            #expect(!FileManager.default.fileExists(atPath: folder.path))
        }
        #expect(!FileManager.default.fileExists(atPath: try #require(locations.widgetSnapshot).path))
        #expect(FileManager.default.fileExists(atPath: kept.path))
        #expect(FileManager.default.fileExists(atPath: locations.temporary.path))
    }

    @Test func eraseDefaultsKeepsSettingsAndRemovesEverythingElse() throws {
        let suite = "offrecord.eraser.test.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let erased = ["authorName", "authorDescription", "offrecord_onboarding_response", "dvx_last_milestone",
                      "offrecord_friday_profile_fingerprint", "offrecord_proactive_reflection_reminder_body",
                      "offrecord.daypartHero.history", "pendingOffRecordRouteURL", "userAIProfile", "reviewManager_entryCount"]
        let kept = ["hasCompletedOnboarding", "appLockEnabled", "iCloudSyncEnabled", FridayAvailability.defaultsKey,
                    JournalSpotlightIndexer.isEnabledDefaultsKey, "selectedTheme", "solyn_reminder_hour", "AppleLanguages"]
        for key in erased + kept {
            defaults.set("value", forKey: key)
        }

        JournalEraser(container: PersistenceController(inMemory: true).container, locations: try temporaryLocations().locations, defaults: defaults, defaultsDomain: suite).eraseDefaults()

        for key in erased {
            #expect(defaults.object(forKey: key) == nil, "\(key) should be erased")
        }
        for key in kept {
            #expect(defaults.object(forKey: key) != nil, "\(key) should be kept")
        }
    }

    // MARK: Helpers

    private func temporaryLocations() throws -> (locations: JournalEraserLocations, root: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("eraser-\(UUID().uuidString)", isDirectory: true)
        let locations = JournalEraserLocations(
            applicationSupport: root.appendingPathComponent("Application Support", isDirectory: true),
            temporary: root.appendingPathComponent("tmp", isDirectory: true),
            widgetSnapshot: root.appendingPathComponent("Group/WidgetSnapshot.json")
        )
        try FileManager.default.createDirectory(at: locations.applicationSupport, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: locations.temporary, withIntermediateDirectories: true)
        return (locations, root)
    }

    private func totalObjectCount(_ container: NSPersistentContainer) throws -> Int {
        try container.managedObjectModel.entities.compactMap(\.name).reduce(0) { total, name in
            total + (try container.viewContext.count(for: NSFetchRequest<NSFetchRequestResult>(entityName: name)))
        }
    }
}
