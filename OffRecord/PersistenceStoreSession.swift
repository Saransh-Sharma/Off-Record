//
//  PersistenceStoreSession.swift
//  OffRecord
//
//  Opens the journal store, remembers why it didn't open, and reopens it with
//  or without iCloud mirroring while the app runs.
//
//  Live iCloud switch (Settings › iCloud Sync):
//  1. Refuses while anything holds managed object IDs across the switch: a
//     capture or its transcription, a photo import, or Erase All Data
//     (`holdReloads`).
//  2. Saves the view context, removes the store from the one coordinator, and
//     loads it again from the same file, with or without
//     `cloudKitContainerOptions`. The container and coordinator stay the same,
//     so `PersistenceController.shared.container` and every service that holds
//     it stay current.
//  3. Resets the view context and bumps `generation`. The app root uses it as a
//     view identity, so every screen and fetch request starts over with no
//     stale objects.
//  4. Posts `.offRecordStoreDidReload`. Spotlight, widgets, and the search
//     index refresh from it; WidgetSnapshotExporter and FridayProfileRebuilder
//     already watch the coordinator, which survives.
//  If the store can't open again, the old setting is tried once more, and the
//  recovery screen covers the app only if that fails too. Nothing is deleted.
//

import CloudKit
import Combine
import CoreData
import os.log

private let storeLogger = Logger(subsystem: "com.singularity.offrecord", category: "PersistenceStore")

extension Notification.Name {
    /// Posted on the main queue after the store reopened (iCloud switch or Try Again).
    static let offRecordStoreDidReload = Notification.Name("offrecord.storeDidReload")
}

/// Where the journal store lives and whether it mirrors to iCloud.
struct PersistenceStoreConfiguration: Equatable {
    var storeURL: URL
    var mirrorsToCloudKit: Bool

    static let storeFileName = "OffRecord.sqlite"
    static let syncPreferenceKey = "iCloudSyncEnabled"
    /// Last iCloud account status the app saw; lets CloudKit start at launch when
    /// iCloud Drive is off, since `ubiquityIdentityToken` only reflects Drive.
    static let lastKnownAccountAvailableKey = "offrecord.iCloud.lastKnownAccountAvailable"

    var isInMemory: Bool { storeURL.path == "/dev/null" }

    static var inMemory: PersistenceStoreConfiguration {
        PersistenceStoreConfiguration(storeURL: URL(fileURLWithPath: "/dev/null"), mirrorsToCloudKit: false)
    }

    /// The app's own store. A unit-test host gets a fresh folder of its own and
    /// never mirrors, so tests can't touch the journal or the developer's iCloud.
    static func app(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        processInfo: ProcessInfo = .processInfo
    ) -> PersistenceStoreConfiguration {
        if isUnitTestHost(processInfo) {
            let folder = fileManager.temporaryDirectory
                .appendingPathComponent("OffRecordUnitTestStore-\(processInfo.processIdentifier)", isDirectory: true)
            try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            return PersistenceStoreConfiguration(storeURL: folder.appendingPathComponent(storeFileName), mirrorsToCloudKit: false)
        }
        return PersistenceStoreConfiguration(
            storeURL: defaultStoreURL(fileManager: fileManager),
            mirrorsToCloudKit: syncPreference(defaults) && iCloudLooksAvailable(defaults: defaults, fileManager: fileManager)
        )
    }

    /// The shared App Group container, so widgets can read the snapshot next to it.
    static func defaultStoreURL(fileManager: FileManager = .default) -> URL {
        if let appGroupURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: PersistenceController.appGroupIdentifier) {
            return appGroupURL.appendingPathComponent(storeFileName)
        }
        return NSPersistentCloudKitContainer.defaultDirectoryURL().appendingPathComponent(storeFileName)
    }

    static func syncPreference(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: syncPreferenceKey) as? Bool ?? true
    }

    static func iCloudLooksAvailable(defaults: UserDefaults = .standard, fileManager: FileManager = .default) -> Bool {
        fileManager.ubiquityIdentityToken != nil || defaults.bool(forKey: lastKnownAccountAvailableKey)
    }

    static func isUnitTestHost(_ processInfo: ProcessInfo = .processInfo) -> Bool {
        processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func makeDescription() -> NSPersistentStoreDescription {
        let description = NSPersistentStoreDescription(url: storeURL)
        if mirrorsToCloudKit && !isInMemory {
            description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: PersistenceController.cloudKitContainerIdentifier
            )
        }
        #if os(iOS) && !targetEnvironment(macCatalyst)
        description.setOption(FileProtectionType.complete as NSObject, forKey: NSPersistentStoreFileProtectionKey)
        #endif
        description.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
        description.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
        // History tracking works with or without CloudKit and lets mirroring resume later.
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        return description
    }
}

/// Why the store didn't open. Holds no journal content.
struct StoreLoadFailure: Equatable {
    let storeURL: URL
    let domain: String
    let code: Int
    let underlyingDescription: String

    init(storeURL: URL, error: NSError) {
        self.storeURL = storeURL
        self.domain = error.domain
        self.code = error.code
        self.underlyingDescription = error.localizedDescription
    }

    /// The short code shown on the recovery screen and in a support email.
    var reference: String { "\(domain) \(code)" }
}

enum StoreReloadOutcome: Equatable {
    case reloaded
    /// Something holds objects across a reload; nothing changed.
    case busy
    /// The new setting didn't open, so the previous one is back.
    case keptPreviousSetting
    /// Neither setting opened; the recovery screen covers the app.
    case failed
}

/// Owns loading for one container. `PersistenceController.shared.session` is the app's.
final class PersistenceStoreSession: ObservableObject {
    let container: NSPersistentCloudKitContainer

    @Published private(set) var configuration: PersistenceStoreConfiguration
    @Published private(set) var loadFailure: StoreLoadFailure?
    /// Bumped after every reopen; the app root uses it as a view identity.
    @Published private(set) var generation = 0
    /// Reasons a reload must wait, such as "erase". See `holdReloads(_:)`.
    @Published private(set) var reloadHolds: Set<String> = []

    var isLoaded: Bool { loadFailure == nil && !container.persistentStoreCoordinator.persistentStores.isEmpty }
    var mirrorsToCloudKit: Bool { isLoaded && configuration.mirrorsToCloudKit }

    init(container: NSPersistentCloudKitContainer, configuration: PersistenceStoreConfiguration) {
        self.container = container
        self.configuration = configuration
        loadFailure = Self.load(container, configuration: configuration)
    }

    // MARK: Holds

    /// Keeps the store from reloading until `releaseReloads(_:)`. Erase All Data
    /// holds it, since it deletes through background contexts.
    @MainActor
    func holdReloads(_ reason: String) {
        reloadHolds.insert(reason)
    }

    @MainActor
    func releaseReloads(_ reason: String) {
        reloadHolds.remove(reason)
    }

    // MARK: Reload

    /// Opens the store again with the same setting. Used by Try Again.
    @MainActor
    @discardableResult
    func retry() -> Bool {
        reopen(with: configuration) == nil
    }

    /// Reopens the store with or without iCloud mirroring.
    @MainActor
    func reload(mirrorsToCloudKit: Bool) -> StoreReloadOutcome {
        guard reloadHolds.isEmpty else { return .busy }
        var next = configuration
        next.mirrorsToCloudKit = mirrorsToCloudKit && !next.isInMemory
        let previous = configuration

        let viewContext = container.viewContext
        if viewContext.hasChanges {
            do {
                try viewContext.save()
            } catch {
                storeLogger.error("Store reload stopped; unsaved changes didn't save: \(error.localizedDescription, privacy: .public)")
                return .busy
            }
        }

        guard reopen(with: next) != nil else { return .reloaded }
        storeLogger.error("Store didn't open with mirroring \(next.mirrorsToCloudKit, privacy: .public); restoring the previous setting.")
        return reopen(with: previous) == nil ? .keptPreviousSetting : .failed
    }

    /// Removes any loaded store and loads `configuration`. Returns the failure, if any.
    @MainActor
    @discardableResult
    private func reopen(with configuration: PersistenceStoreConfiguration) -> StoreLoadFailure? {
        let failure = Self.load(container, configuration: configuration)
        container.viewContext.reset()
        self.configuration = configuration
        loadFailure = failure
        generation += 1
        if failure == nil {
            NotificationCenter.default.post(name: .offRecordStoreDidReload, object: self)
        }
        return failure
    }

    /// Loads `configuration` into `container`, replacing what's there. Never deletes files.
    @discardableResult
    static func load(_ container: NSPersistentContainer, configuration: PersistenceStoreConfiguration) -> StoreLoadFailure? {
        let coordinator = container.persistentStoreCoordinator
        for store in coordinator.persistentStores {
            do {
                try coordinator.remove(store)
            } catch {
                storeLogger.error("Couldn't close the store before reopening: \(error.localizedDescription, privacy: .public)")
                return StoreLoadFailure(storeURL: configuration.storeURL, error: error as NSError)
            }
        }

        let description = configuration.makeDescription()
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]

        var failure: StoreLoadFailure?
        container.loadPersistentStores { storeDescription, error in
            guard let error = error as NSError? else { return }
            storeLogger.error("Failed to load persistent store at \(storeDescription.url?.absoluteString ?? "unknown", privacy: .public): \(error.domain, privacy: .public) \(error.code, privacy: .public) \(error.localizedDescription, privacy: .public)")
            failure = StoreLoadFailure(storeURL: configuration.storeURL, error: error)
        }
        if failure == nil, coordinator.persistentStores.isEmpty {
            failure = StoreLoadFailure(
                storeURL: configuration.storeURL,
                error: NSError(domain: NSCocoaErrorDomain, code: NSPersistentStoreOpenError)
            )
        }
        return failure
    }
}
