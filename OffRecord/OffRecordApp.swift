//
//  solynApp.swift
//  OffRecord
//
//  Main entry point for the OffRecord AI Journal voice diary app.
//  A privacy-focused journaling app with voice-to-text transcription.
//
//  Created by Karthikeyan NG on 01/12/25.
//

import SwiftUI
import WidgetKit
import CoreData
import CoreSpotlight
import os.log
import UserNotifications

private let appLogger = Logger(subsystem: "com.singularity.offrecord", category: "App")

/// Main app entry point.
/// Manages app lifecycle, authentication state, and theme.
@main
struct OffRecordApp: App {
    
    // MARK: - Properties
    let persistenceController = PersistenceController.shared
    @ObservedObject private var lockManager = AppLockManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var navigationRouter = OffRecordNavigationRouter.shared
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var isShowingSplash = true

    init() {
        UNUserNotificationCenter.current().delegate = OffRecordNotificationDelegate.shared
        ScreenshotDataSeeder.seedIfNeeded(context: persistenceController.container.viewContext)
        UITestDataSeeder.seedIfNeeded(context: persistenceController.container.viewContext)
        ReminderManager.shared.reconcileScheduleIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                Group {
                    if !hasCompletedOnboarding {
                        OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
                    } else {
                        ZStack {
                            ContentView()

                            // Show lock screen if app lock is enabled and not unlocked
                            if lockManager.isEnabled && !lockManager.isUnlocked {
                                LockScreenView()
                                    .transition(.opacity)
                            }
                        }
                        .animation(.easeInOut(duration: 0.2), value: lockManager.isUnlocked)
                    }
                }

                if isShowingSplash {
                    SplashScreenView {
                        isShowingSplash = false
                    }
                    .zIndex(1)
                    .transition(.opacity)
                }
            }
            .environment(\.managedObjectContext, persistenceController.container.viewContext)
            .animation(.easeInOut(duration: 0.3), value: hasCompletedOnboarding)
            .preferredColorScheme(themeManager.selectedTheme.colorScheme)
            .tint(themeManager.selectedTheme.accentColor)
            .onOpenURL { url in
                guard let route = OffRecordNavigationRouter.route(from: url) else { return }
                navigationRouter.route(route, canNavigate: canNavigateToPrivateContent)
            }
            .onContinueUserActivity(CSSearchableItemActionType) { userActivity in
                _ = navigationRouter.route(userActivity: userActivity, canNavigate: canNavigateToPrivateContent)
            }
            .onContinueUserActivity(JournalSpotlightIndexer.viewEntryActivityType) { userActivity in
                _ = navigationRouter.route(userActivity: userActivity, canNavigate: canNavigateToPrivateContent)
            }
            .onContinueUserActivity("com.singularity.offrecord.today") { userActivity in
                _ = navigationRouter.route(userActivity: userActivity, canNavigate: canNavigateToPrivateContent)
            }
            .onContinueUserActivity("com.singularity.offrecord.searchTimeline") { userActivity in
                _ = navigationRouter.route(userActivity: userActivity, canNavigate: canNavigateToPrivateContent)
            }
            .onContinueUserActivity("com.singularity.offrecord.friday") { userActivity in
                _ = navigationRouter.route(userActivity: userActivity, canNavigate: canNavigateToPrivateContent)
            }
            .onChange(of: hasCompletedOnboarding) { _, _ in
                resumeDeferredRoutesIfPossible()
            }
            .onChange(of: lockManager.isUnlocked) { _, _ in
                resumeDeferredRoutesIfPossible()
            }
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .background:
                    if lockManager.isEnabled {
                        lockManager.lock()
                    }
                    // Refresh widgets when app goes to background
                    WidgetCenter.shared.reloadAllTimelines()
                    runAudioCleanup()
                case .active:
                    consumeLegacyAndStoredRoutes()
                    resumeDeferredRoutesIfPossible()
                    JournalSpotlightIndexer.shared.rebuild(entries: startedEntriesForIndexing())
                    ReminderManager.shared.reconcileScheduleIfNeeded()
                default:
                    break
                }
            }
        }
    }

    private var canNavigateToPrivateContent: Bool {
        hasCompletedOnboarding && (!lockManager.isEnabled || lockManager.isUnlocked)
    }

    private func consumeLegacyAndStoredRoutes() {
        if UserDefaults.standard.bool(forKey: "shouldStartRecording") {
            UserDefaults.standard.set(false, forKey: "shouldStartRecording")
            navigationRouter.route(.record, canNavigate: canNavigateToPrivateContent)
        }
        navigationRouter.consumeStoredRoute(canNavigate: canNavigateToPrivateContent)
    }

    private func resumeDeferredRoutesIfPossible() {
        navigationRouter.resumeDeferredRouteIfPossible(canNavigate: canNavigateToPrivateContent)
    }

    private func startedEntriesForIndexing() -> [DiaryEntry] {
        let request: NSFetchRequest<DiaryEntry> = DiaryEntry.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \DiaryEntry.updatedAt, ascending: false)]
        request.fetchLimit = 300
        return ((try? persistenceController.container.viewContext.fetch(request)) ?? []).startedEntries
    }

    private func runAudioCleanup() {
        #if os(iOS)
        let context = persistenceController.container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        context.perform {
            do {
                let fetchRequest: NSFetchRequest<DiaryEntry> = DiaryEntry.fetchRequest()
                fetchRequest.propertiesToFetch = ["audioFileName"]
                fetchRequest.returnsObjectsAsFaults = false

                let results = try context.fetch(fetchRequest)
                let fileNames = results.compactMap { entry in
                    entry.value(forKey: "audioFileName") as? String
                }.filter { !$0.isEmpty }

                let fileManager = FileManager.default
                guard let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                    appLogger.warning("Audio cleanup could not resolve Application Support directory; falling back to empty keep list.")
                    AudioRecorder.cleanupOrphanedRecordings(keepURLs: [])
                    return
                }

                let recordingsDirectory = base.appendingPathComponent("Recordings", isDirectory: true)
                let keepURLs = Set(fileNames.map { recordingsDirectory.appendingPathComponent($0) })

                AudioRecorder.cleanupOrphanedRecordings(keepURLs: keepURLs)
            } catch {
                appLogger.error("Audio cleanup failed to fetch recording references: \(error.localizedDescription, privacy: .public)")
                AudioRecorder.cleanupOrphanedRecordings(keepURLs: [])
            }
        }
        #endif
    }
}

final class OffRecordNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = OffRecordNotificationDelegate()

    private override init() {}

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        ReminderManager.shared.reconcileScheduleIfNeeded()
        return [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        ReminderManager.shared.reconcileScheduleIfNeeded()
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let startRecordingFromSiri = Notification.Name("startRecordingFromSiri")
}
