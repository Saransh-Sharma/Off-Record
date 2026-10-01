//
//  JournalEraser.swift
//  OffRecord
//
//  Erase All Data (Settings). Removes every entry and everything derived
//  from the journal, then the app lands on a fresh Today without a relaunch.
//
//  Removed:
//  - every Core Data object (entries, blocks, recordings, photos, tags,
//    journals, watch receipts, and all AIState rows: Weekly Reflection,
//    proactive cards, legacy Friday state). Deletes go through a context, so
//    with iCloud sync on they sync as deletes and leave iCloud too.
//  - files: Recordings, Photos, FridayLocal (Friday's profile, chat, memory
//    edits, and caches), imported watch files, temporary exports
//  - the search index, the Spotlight domain, the widget snapshot, delivered
//    notifications, and leftover Live Activities
//  - UserDefaults the app owns, except `keptDefaultsKeys`
//
//  Kept: onboarding stays complete, and settings that hold no journal content
//  stay as they are (Lock, iCloud, Spotlight, Friday, theme, reminders, goal,
//  Apple Health, transcription consent). Moods already saved to Apple Health
//  stay in Health.
//

import CoreData
import Foundation
import os.log
import UserNotifications
import WidgetKit

private let eraserLogger = Logger(subsystem: "com.singularity.offrecord", category: "JournalEraser")

extension Notification.Name {
    /// Posted on the main queue after Erase All Data finishes.
    static let offRecordDidEraseAllData = Notification.Name("offrecord.didEraseAllData")
}

/// Where the app keeps journal files. Tests pass temporary folders.
struct JournalEraserLocations {
    var applicationSupport: URL
    var temporary: URL
    var widgetSnapshot: URL?

    /// Folders under Application Support that hold journal content.
    static let journalFolderNames = ["Recordings", "Photos", "FridayLocal"]

    var journalFolders: [URL] {
        Self.journalFolderNames.map { applicationSupport.appendingPathComponent($0, isDirectory: true) }
    }

    static var live: JournalEraserLocations {
        JournalEraserLocations(
            applicationSupport: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!,
            temporary: FileManager.default.temporaryDirectory,
            widgetSnapshot: WidgetSnapshotStore.fileURL
        )
    }
}

@MainActor
struct JournalEraser {
    /// Settings that survive an erase. None hold journal content, and some
    /// (iCloud, Spotlight, Friday) would otherwise switch back on by default.
    static let keptDefaultsKeys: Set<String> = [
        "hasCompletedOnboarding",
        "appLockEnabled",
        "iCloudSyncEnabled",
        JournalSpotlightIndexer.isEnabledDefaultsKey,
        FridayAvailability.defaultsKey,
        "selectedTheme",
        "solyn_reminder_enabled",
        "solyn_reminder_hour",
        "solyn_reminder_minute",
        "offrecord_reminder_smart_prompts",
        "dvx_goal_enabled",
        "dvx_goal_target",
        "dvx_goal_notify",
        HealthStateOfMindWriter.enabledKey,
        HealthStateOfMindWriter.offeredKey,
        SpeechTranscriptionConsent.appleSpeechProcessingKey,
        CaptureController.liveTranscriptPreferenceKey,
    ]

    /// Keys written by Apple frameworks into the app's domain; never ours to remove.
    private static let systemKeyPrefixes = ["Apple", "NS", "com.apple.", "WebKit", "AK", "PK"]

    /// Objects deleted per save, to keep memory flat on large journals.
    static let batchSize = 200

    let container: NSPersistentContainer
    let locations: JournalEraserLocations
    let defaults: UserDefaults
    /// The defaults domain to clear: the bundle ID for `.standard`, or a suite name.
    let defaultsDomain: String?
    let fileManager: FileManager

    init(
        container: NSPersistentContainer,
        locations: JournalEraserLocations,
        defaults: UserDefaults = .standard,
        defaultsDomain: String? = Bundle.main.bundleIdentifier,
        fileManager: FileManager = .default
    ) {
        self.container = container
        self.locations = locations
        self.defaults = defaults
        self.defaultsDomain = defaultsDomain
        self.fileManager = fileManager
    }

    // MARK: Store

    /// Deletes every object in the store, entries first. Returns how many were deleted.
    @discardableResult
    func eraseStore() async throws -> Int {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        let entityNames = Self.deletionOrder(container.managedObjectModel)
        let batchSize = Self.batchSize
        return try await context.perform {
            var deleted = 0
            for name in entityNames {
                while true {
                    let request = NSFetchRequest<NSManagedObject>(entityName: name)
                    request.includesPropertyValues = false
                    request.includesSubentities = false
                    request.fetchLimit = batchSize
                    let objects = try context.fetch(request)
                    guard !objects.isEmpty else { break }
                    objects.forEach(context.delete)
                    try context.save()
                    deleted += objects.count
                    context.reset()
                }
            }
            return deleted
        }
    }

    /// Entries go first so their cascades remove blocks and attachments in the same saves.
    static func deletionOrder(_ model: NSManagedObjectModel) -> [String] {
        let names = model.entities.filter { !$0.isAbstract }.compactMap(\.name)
        let first = names.filter { $0 == "DiaryEntry" }
        return first + names.filter { $0 != "DiaryEntry" }.sorted()
    }

    // MARK: Files

    /// Removes journal folders, temporary files, and the widget snapshot.
    func eraseFiles() {
        for folder in locations.journalFolders where fileManager.fileExists(atPath: folder.path) {
            remove(folder)
        }
        let temporaryItems = (try? fileManager.contentsOfDirectory(at: locations.temporary, includingPropertiesForKeys: nil)) ?? []
        temporaryItems.forEach(remove)
        if let snapshot = locations.widgetSnapshot, fileManager.fileExists(atPath: snapshot.path) {
            remove(snapshot)
        }
    }

    private func remove(_ url: URL) {
        do {
            try fileManager.removeItem(at: url)
        } catch {
            eraserLogger.error("Couldn’t remove \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Defaults

    /// Removes the app's own keys except `keptDefaultsKeys`.
    func eraseDefaults() {
        guard let domain = defaultsDomain, let values = defaults.persistentDomain(forName: domain) else { return }
        for key in values.keys where Self.shouldErase(key) {
            defaults.removeObject(forKey: key)
        }
    }

    static func shouldErase(_ key: String) -> Bool {
        guard !keptDefaultsKeys.contains(key) else { return false }
        return !systemKeyPrefixes.contains { key.hasPrefix($0) }
    }

    // MARK: Whole app

    /// Erases everything for the running app and resets in-memory state, then
    /// posts `offRecordDidEraseAllData` so the tabs rebuild on a fresh Today.
    static func eraseEverything(container: NSPersistentContainer = PersistenceController.shared.container) async throws {
        let eraser = JournalEraser(container: container, locations: .live)

        // In-memory state first, so nothing re-saves old content while rows go.
        WeeklyReflectionController.shared.resetAfterErase()
        ProactiveReflectionController.shared.clearDerivedState(includingFeedback: true)
        FridayAvailability.forgetEverything()
        SemanticMemoryIndexController.shared.deleteIndex()
        JournalSpotlightIndexer.shared.deleteAll()

        let deleted = try await eraser.eraseStore()
        eraser.eraseFiles()
        eraser.eraseDefaults()

        // Weekly Reflection settings live with its reports; save them again on their own.
        WeeklyReflectionController.shared.resetAfterErase()
        let center = UNUserNotificationCenter.current()
        center.removeAllDeliveredNotifications()
        ReminderManager.shared.reconcileScheduleIfNeeded()
        await CaptureLiveActivityManager.shared.endOrphanedActivities()
        WidgetCenter.shared.reloadAllTimelines()
        WidgetSnapshotExporter.shared.scheduleExport(after: .milliseconds(300))

        let router = OffRecordNavigationRouter.shared
        router.fridayQuestion = nil
        router.routedEntryID = nil
        router.routedWeeklyReflectionID = nil
        router.shouldOpenCurrentWeeklyReflection = false
        router.timelineSearchText = ""
        router.pendingTypedNote = nil
        router.selectedTab = .today

        eraserLogger.notice("Erased all data: \(deleted, privacy: .public) objects.")
        NotificationCenter.default.post(name: .offRecordDidEraseAllData, object: nil)
    }
}
