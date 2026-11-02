//
//  CloudSyncMonitor.swift
//  OffRecord
//
//  Watches NSPersistentCloudKitContainer events and the iCloud account, and
//  publishes a CloudSyncStatus for Settings. Talks only to the user's own
//  CloudKit container; it reads status and never sends anything.
//

import CloudKit
import Combine
import CoreData
import os.log

private let syncMonitorLogger = Logger(subsystem: "com.singularity.offrecord", category: "CloudSync")

@MainActor
final class CloudSyncMonitor: ObservableObject {
    static let shared = CloudSyncMonitor()

    static let lastSuccessfulSyncKey = "offrecord.iCloud.lastSuccessfulSync"

    @Published private(set) var status: CloudSyncStatus
    /// Set when mirroring was turned on in this process and hasn't started yet.
    @Published private(set) var mirroringStartRequestedAt: Date?
    /// Set when the iCloud switch couldn't reopen the store with the new setting.
    /// Lives here because the switch rebuilds every screen, Settings included.
    @Published var switchDidNotApply = false
    /// Settings scrolls back to the iCloud card after the switch rebuilds it.
    private(set) var pendingScrollTarget: String?

    private let defaults: UserDefaults
    private var observers: [NSObjectProtocol] = []
    private var accountTask: Task<Void, Never>?
    private var isStarted = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        status = CloudSyncStatus(lastSuccessfulSync: defaults.object(forKey: Self.lastSuccessfulSyncKey) as? Date)
    }

    func start(container: NSPersistentCloudKitContainer) {
        guard !isStarted else { return }
        isStarted = true
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: container,
            queue: .main
        ) { [weak self] note in
            guard let raw = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event,
                  let event = CloudSyncEvent(raw) else { return }
            MainActor.assumeIsolated { self?.record(event) }
        })
        observers.append(center.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAccountStatus() }
        })
        observers.append(center.addObserver(forName: .offRecordStoreDidReload, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.storeDidReload() }
        })
        refreshAccountStatus()
    }

    /// Asks CloudKit for the account status. CloudKit is the source of truth;
    /// `ubiquityIdentityToken` only reflects iCloud Drive.
    func refreshAccountStatus() {
        accountTask?.cancel()
        accountTask = Task { [weak self] in
            let state: CloudAccountState
            do {
                state = CloudAccountState(try await CKContainer(identifier: PersistenceController.cloudKitContainerIdentifier).accountStatus())
            } catch {
                syncMonitorLogger.warning("iCloud account status unavailable: \(error.localizedDescription, privacy: .public)")
                state = .unknown
            }
            guard !Task.isCancelled else { return }
            self?.apply(account: state)
        }
    }

    func record(_ event: CloudSyncEvent) {
        status.apply(event)
        if status.hasStartedMirroring {
            mirroringStartRequestedAt = nil
        }
        if let date = status.lastSuccessfulSync {
            defaults.set(date, forKey: Self.lastSuccessfulSyncKey)
        }
        if let problem = status.lastProblem, event.endDate != nil, !event.succeeded {
            syncMonitorLogger.error("iCloud \(String(describing: event.kind), privacy: .public) failed: \(String(describing: problem), privacy: .public)")
        }
    }

    func apply(account: CloudAccountState) {
        status.apply(account: account)
        if account != .unknown {
            defaults.set(account == .available, forKey: PersistenceStoreConfiguration.lastKnownAccountAvailableKey)
        }
    }

    /// Called right after the iCloud switch reopened the store.
    func noteSwitchApplied(mirroring: Bool, at date: Date = Date()) {
        mirroringStartRequestedAt = mirroring ? date : nil
        pendingScrollTarget = "icloud"
    }

    func noteSwitchDidNotApply() {
        switchDidNotApply = true
        pendingScrollTarget = "icloud"
    }

    /// The Settings card to scroll to once, after a switch rebuilt Settings.
    func takeScrollTarget() -> String? {
        defer { pendingScrollTarget = nil }
        return pendingScrollTarget
    }

    private func storeDidReload() {
        status.storeDidReload()
        refreshAccountStatus()
    }

    /// True when mirroring was turned on a while ago and never started, so the
    /// live switch didn't take. Settings then asks for a restart.
    func mirroringLooksStalled(now: Date = Date(), after timeout: TimeInterval = 20) -> Bool {
        guard let requested = mirroringStartRequestedAt else { return false }
        return !status.hasStartedMirroring && now.timeIntervalSince(requested) >= timeout
    }
}
