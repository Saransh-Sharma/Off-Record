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

    // MARK: - Initialization
    
    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "OffRecord")

        // Configure store location
        // Data is stored in the shared App Group container so widgets can access it
        let storeURL: URL
        if inMemory {
            storeURL = URL(fileURLWithPath: "/dev/null")
        } else if let appGroupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: PersistenceController.appGroupIdentifier) {
            storeURL = appGroupURL.appendingPathComponent("OffRecord.sqlite")
        } else {
            // Fallback to default directory if App Group is unavailable
            storeURL = NSPersistentCloudKitContainer.defaultDirectoryURL().appendingPathComponent("OffRecord.sqlite")
        }

        let description = NSPersistentStoreDescription(url: storeURL)

        // Only enable CloudKit if iCloud is available and properly configured.
        if !inMemory && PersistenceController.shouldEnableCloudKit {
            description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: PersistenceController.cloudKitContainerIdentifier
            )
        }

        // File protection (iOS only - not available on macOS)
        #if os(iOS)
        description.setOption(FileProtectionType.complete as NSObject,
                              forKey: NSPersistentStoreFileProtectionKey)
        #endif

        // Enable history tracking (works with or without CloudKit)
        description.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
        description.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        container.persistentStoreDescriptions = [description]
        let persistentContainer = container

        container.loadPersistentStores { (storeDescription, error) in
            if let error = error as NSError? {
                persistenceLogger.error("Failed to load persistent store at \(storeDescription.url?.absoluteString ?? "unknown", privacy: .public): \(error.localizedDescription, privacy: .public) \(String(describing: error.userInfo), privacy: .public)")
            } else if !inMemory {
                PhotoStorageManager.shared.migrateLegacyPhotos(in: persistentContainer.viewContext)
            }
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
            // Refresh the view context when remote changes arrive
            viewContext.refreshAllObjects()
        }
    }

    /// Check if CloudKit should be enabled (requires both iCloud availability and user preference)
    private static var shouldEnableCloudKit: Bool {
        let userEnabled = UserDefaults.standard.object(forKey: "iCloudSyncEnabled") as? Bool ?? true
        return userEnabled && FileManager.default.ubiquityIdentityToken != nil
    }

    // MARK: - Sync Control

    /// Check if iCloud is available
    static var isCloudAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    /// Store the user's CloudKit preference. The persistent store reads it during app launch.
    func setCloudSyncEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "iCloudSyncEnabled")
        persistenceLogger.info("CloudKit sync preference changed to \(enabled, privacy: .public); restart required for store reconfiguration.")
    }
}
