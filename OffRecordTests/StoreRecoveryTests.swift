import CoreData
import Foundation
import Testing
@testable import OffRecord

/// The store-load failure path and the live reopen behind the iCloud switch,
/// against SQLite files in a temporary folder. CloudKit itself isn't reachable
/// from tests, so mirroring is off here; the reopen path is the same.
@MainActor
@Suite(.serialized)
struct StoreRecoveryTests {

    // MARK: Helpers

    private func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("StoreRecoveryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Shares the app's model so entity classes resolve to one description.
    private func makeContainer() -> NSPersistentCloudKitContainer {
        NSPersistentCloudKitContainer(
            name: "OffRecord",
            managedObjectModel: PersistenceController.shared.container.managedObjectModel
        )
    }

    private func makeSession(at storeURL: URL) -> PersistenceStoreSession {
        PersistenceStoreSession(
            container: makeContainer(),
            configuration: PersistenceStoreConfiguration(storeURL: storeURL, mirrorsToCloudKit: false)
        )
    }

    @discardableResult
    private func insertEntry(_ text: String, in context: NSManagedObjectContext) throws -> NSManagedObject {
        let entry = NSEntityDescription.insertNewObject(forEntityName: "DiaryEntry", into: context)
        entry.setValue(UUID(), forKey: "id")
        entry.setValue(Date(), forKey: "date")
        entry.setValue(Date(), forKey: "updatedAt")
        entry.setValue(text, forKey: "text")
        try context.save()
        return entry
    }

    private func entryCount(_ context: NSManagedObjectContext) throws -> Int {
        try context.count(for: NSFetchRequest<NSManagedObject>(entityName: "DiaryEntry"))
    }

    // MARK: Load failure

    @Test func unreadableStoreReportsAFailureAndKeepsTheFile() throws {
        let folder = try temporaryFolder()
        let storeURL = folder.appendingPathComponent("OffRecord.sqlite")
        let garbage = Data("this is not a database".utf8)
        try garbage.write(to: storeURL)

        let session = makeSession(at: storeURL)

        let failure = try #require(session.loadFailure)
        #expect(!session.isLoaded)
        #expect(failure.storeURL == storeURL)
        #expect(!failure.reference.isEmpty)
        // Never deleted or replaced.
        #expect(try Data(contentsOf: storeURL) == garbage)
    }

    @Test func tryAgainOpensTheStoreOnceItCanBeRead() throws {
        let folder = try temporaryFolder()
        let storeURL = folder.appendingPathComponent("OffRecord.sqlite")
        try Data("still not a database".utf8).write(to: storeURL)
        let session = makeSession(at: storeURL)
        #expect(session.loadFailure != nil)

        // Still unreadable: Try Again fails and the file stays.
        #expect(!session.retry())
        #expect(FileManager.default.fileExists(atPath: storeURL.path))

        // Someone restores a good file (for example from an exported copy).
        try FileManager.default.removeItem(at: storeURL)
        let generation = session.generation
        var reloadNotes = 0
        let observer = NotificationCenter.default.addObserver(forName: .offRecordStoreDidReload, object: session, queue: nil) { _ in
            reloadNotes += 1
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        #expect(session.retry())
        #expect(session.loadFailure == nil)
        #expect(session.isLoaded)
        #expect(session.generation == generation + 1)
        #expect(reloadNotes == 1)
        try insertEntry("Back again.", in: session.container.viewContext)
        #expect(try entryCount(session.container.viewContext) == 1)
    }

    // MARK: Live reopen (the iCloud switch)

    @Test func reopenKeepsEntriesAndTheSameContainer() throws {
        let storeURL = try temporaryFolder().appendingPathComponent("OffRecord.sqlite")
        let session = makeSession(at: storeURL)
        let container = session.container
        let coordinator = container.persistentStoreCoordinator
        try insertEntry("Before the switch.", in: container.viewContext)

        #expect(session.reload(mirrorsToCloudKit: false) == .reloaded)

        #expect(session.container === container)
        #expect(container.persistentStoreCoordinator === coordinator)
        #expect(coordinator.persistentStores.count == 1)
        #expect(session.generation == 1)
        #expect(try entryCount(container.viewContext) == 1)
        // Writes work against the reopened store.
        try insertEntry("After the switch.", in: container.viewContext)
        #expect(try entryCount(container.newBackgroundContext()) == 2)
    }

    @Test func reopenSavesPendingChangesFirst() throws {
        let storeURL = try temporaryFolder().appendingPathComponent("OffRecord.sqlite")
        let session = makeSession(at: storeURL)
        let context = session.container.viewContext
        let entry = NSEntityDescription.insertNewObject(forEntityName: "DiaryEntry", into: context)
        entry.setValue(UUID(), forKey: "id")
        entry.setValue("Typed but not saved.", forKey: "text")
        #expect(context.hasChanges)

        #expect(session.reload(mirrorsToCloudKit: false) == .reloaded)

        #expect(!context.hasChanges)
        #expect(try entryCount(context) == 1)
    }

    @Test func reopenWaitsWhileHeld() throws {
        let storeURL = try temporaryFolder().appendingPathComponent("OffRecord.sqlite")
        let session = makeSession(at: storeURL)
        session.holdReloads("erase")

        #expect(session.reload(mirrorsToCloudKit: true) == .busy)
        #expect(session.generation == 0)
        #expect(!session.configuration.mirrorsToCloudKit)

        session.releaseReloads("erase")
        #expect(session.reload(mirrorsToCloudKit: false) == .reloaded)
    }

    @Test func reopenWithMirroringChangesTheDescription() throws {
        let storeURL = try temporaryFolder().appendingPathComponent("OffRecord.sqlite")
        let session = makeSession(at: storeURL)
        #expect(session.container.persistentStoreDescriptions.allSatisfy { $0.cloudKitContainerOptions == nil })

        // Tests have no iCloud entitlement, so mirroring can't start, but the store
        // still opens with the option set, which is what Erase All Data reads.
        #expect(session.reload(mirrorsToCloudKit: true) == .reloaded)
        #expect(session.configuration.mirrorsToCloudKit)
        #expect(session.container.persistentStoreDescriptions.first?.cloudKitContainerOptions?.containerIdentifier
            == PersistenceController.cloudKitContainerIdentifier)

        #expect(session.reload(mirrorsToCloudKit: false) == .reloaded)
        #expect(session.container.persistentStoreDescriptions.allSatisfy { $0.cloudKitContainerOptions == nil })
    }

    // MARK: Configuration

    @Test func descriptionsKeepHistoryAndNeverMirrorInMemory() {
        let mirrored = PersistenceStoreConfiguration(storeURL: URL(fileURLWithPath: "/tmp/OffRecord.sqlite"), mirrorsToCloudKit: true)
            .makeDescription()
        #expect(mirrored.cloudKitContainerOptions?.containerIdentifier == PersistenceController.cloudKitContainerIdentifier)
        #expect(mirrored.options[NSPersistentHistoryTrackingKey] as? NSNumber == true)
        #expect(mirrored.options[NSPersistentStoreRemoteChangeNotificationPostOptionKey] as? NSNumber == true)

        var memory = PersistenceStoreConfiguration.inMemory
        memory.mirrorsToCloudKit = true
        #expect(memory.makeDescription().cloudKitContainerOptions == nil)
    }

    @Test func unitTestHostUsesItsOwnStoreWithoutICloud() {
        let configuration = PersistenceStoreConfiguration.app()
        #expect(PersistenceStoreConfiguration.isUnitTestHost())
        #expect(!configuration.mirrorsToCloudKit)
        #expect(configuration.storeURL.path.hasPrefix(FileManager.default.temporaryDirectory.path))
    }

    // MARK: Export a Copy

    @Test func exportCopiesTheStoreAndItsSidecars() throws {
        let folder = try temporaryFolder()
        let storeURL = folder.appendingPathComponent("OffRecord.sqlite")
        try Data("db".utf8).write(to: storeURL)
        try Data("wal".utf8).write(to: folder.appendingPathComponent("OffRecord.sqlite-wal"))
        try Data("shm".utf8).write(to: folder.appendingPathComponent("OffRecord.sqlite-shm"))
        let external = folder.appendingPathComponent(".OffRecord_SUPPORT/_EXTERNAL_DATA", isDirectory: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        try Data("photo".utf8).write(to: external.appendingPathComponent("photo-bytes"))
        // Other files in the App Group folder aren't part of the store.
        try Data("{}".utf8).write(to: folder.appendingPathComponent("widget-snapshot.json"))

        let destination = try temporaryFolder()
        let copy = try StoreFileCopier.copyStoreFiles(of: storeURL, into: destination)

        let names = Set(try FileManager.default.contentsOfDirectory(atPath: copy.path))
        #expect(names == ["OffRecord.sqlite", "OffRecord.sqlite-wal", "OffRecord.sqlite-shm", ".OffRecord_SUPPORT"])
        #expect(try Data(contentsOf: copy.appendingPathComponent(".OffRecord_SUPPORT/_EXTERNAL_DATA/photo-bytes")) == Data("photo".utf8))
        // Originals stay.
        #expect(try Data(contentsOf: storeURL) == Data("db".utf8))
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("OffRecord.sqlite-wal").path))
    }

    @Test func shareableArchiveIsAZip() throws {
        let folder = try temporaryFolder()
        let storeURL = folder.appendingPathComponent("OffRecord.sqlite")
        try Data("not a database".utf8).write(to: storeURL)

        let archive = try StoreFileCopier.makeShareableArchive(of: storeURL)
        defer { try? FileManager.default.removeItem(at: archive) }

        #expect(archive.pathExtension == "zip")
        #expect(archive.lastPathComponent.hasPrefix("OffRecord Store Copy"))
        let header = try Data(contentsOf: archive).prefix(2)
        #expect(header == Data("PK".utf8))
    }

    @Test func exportWithNoStoreFilesThrows() throws {
        let storeURL = try temporaryFolder().appendingPathComponent("OffRecord.sqlite")
        #expect(throws: (any Error).self) {
            try StoreFileCopier.copyStoreFiles(of: storeURL, into: try temporaryFolder())
        }
    }

    // MARK: Contact Support

    @Test func supportMailCarriesOnlyTheCodeAndVersion() throws {
        let url = try #require(StoreRecoveryView.supportMailURL(reference: "NSCocoaErrorDomain 134110"))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        #expect(components.scheme == "mailto")
        #expect(components.path == "saransh1337@gmail.com")
        let body = try #require(components.queryItems?.first { $0.name == "body" }?.value)
        #expect(body.contains("NSCocoaErrorDomain 134110"))
        #expect(body.contains("OffRecord "))
    }
}
