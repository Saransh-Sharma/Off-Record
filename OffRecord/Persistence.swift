//
//  Persistence.swift
//  OffRecord
//
//  Core Data persistence controller with CloudKit sync support.
//  All data is stored locally and optionally synced via user's personal iCloud.
//
//  Created by Karthikeyan NG on 01/12/25.
//

import CoreData
import CloudKit
import os.log

private let persistenceLogger = Logger(subsystem: "com.singularity.offrecord", category: "Persistence")

/// Manages Core Data persistence with optional CloudKit synchronization.
/// Data is stored locally on device and synced through user's personal iCloud account.
struct PersistenceController {
    
    // MARK: - Shared Instance
    
    static let shared = PersistenceController()

    /// App Group identifier for sharing data with widgets
    static let appGroupIdentifier = "group.com.singularity.offrecord"

    /// Private CloudKit container used for Core Data mirroring.
    static let cloudKitContainerIdentifier = "iCloud.com.singularity.offrecord"

    @MainActor
    static let preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        for i in 0..<10 {
            let entry = DiaryEntry(context: viewContext)
            let now = Calendar.current.date(byAdding: .day, value: -i, to: Date())!
            entry.id = UUID()
            entry.date = now
            entry.createdAt = now
            entry.updatedAt = now
            entry.text = "Sample entry for preview day \(i + 1)"
            entry.isStarred = i % 3 == 0
            JournalBlockTimelineStore.backfillBlocksIfNeeded(for: entry, in: viewContext)
        }
        do {
            try viewContext.save()
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        return result
    }()

    let container: NSPersistentCloudKitContainer
    /// Loading state for `container`: why it didn't open, and the live iCloud switch.
    let session: PersistenceStoreSession

    // MARK: - Initialization
    
    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "OffRecord")

        // The store lives in the App Group container so widgets can read the snapshot
        // beside it. Loading, the iCloud setting, and failures live in the session.
        session = PersistenceStoreSession(
            container: container,
            configuration: inMemory ? .inMemory : .app()
        )
        if !inMemory && session.isLoaded {
            PhotoStorageManager.shared.migrateLegacyPhotos(in: container.viewContext)
        }

        // Configure view context
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        // Listen for remote changes (only relevant when CloudKit is enabled)
        let coordinator = container.persistentStoreCoordinator
        let viewContext = container.viewContext
        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: coordinator,
            queue: .main
        ) { _ in
            // Refresh the view context when remote changes arrive. This also fires for the
            // app's own saves, so it leaves the search index alone; the index compares
            // entries against what it holds before each search.
            viewContext.refreshAllObjects()
        }
    }

    // MARK: - Sync Control

    /// Check if iCloud is available
    static var isCloudAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    /// Stores the user's CloudKit preference and reopens the store with or without
    /// mirroring. The preference stays as it was unless the store reopened with it.
    @MainActor
    @discardableResult
    func setCloudSyncEnabled(_ enabled: Bool) -> StoreReloadOutcome {
        let outcome = session.reload(mirrorsToCloudKit: enabled)
        if outcome == .reloaded {
            UserDefaults.standard.set(enabled, forKey: PersistenceStoreConfiguration.syncPreferenceKey)
        }
        persistenceLogger.info("CloudKit sync preference \(enabled, privacy: .public): \(String(describing: outcome), privacy: .public)")
        return outcome
    }
}
