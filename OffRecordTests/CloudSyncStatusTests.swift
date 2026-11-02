import CloudKit
import Foundation
import Testing
@testable import OffRecord

/// iCloud Sync status, reduced from synthetic events. `NSPersistentCloudKitContainer.Event`
/// has no public initializer, so these feed `CloudSyncEvent` values instead.
@MainActor
@Suite(.serialized)
struct CloudSyncStatusTests {

    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func event(
        _ kind: CloudSyncEvent.Kind,
        id: UUID = UUID(),
        endsAfter seconds: TimeInterval? = nil,
        succeeded: Bool = true,
        error: Error? = nil
    ) -> CloudSyncEvent {
        CloudSyncEvent(
            id: id,
            kind: kind,
            startDate: start,
            endDate: seconds.map { start.addingTimeInterval($0) },
            succeeded: succeeded,
            problem: succeeded || seconds == nil ? nil : CloudSyncProblem(error: error)
        )
    }

    // MARK: Reducer

    @Test func runningExportShowsSyncingThenLastSynced() {
        let id = UUID()
        var status = CloudSyncStatus(account: .available)

        status.apply(event(.export, id: id))
        #expect(status.isSyncing)
        #expect(status.summary(isEnabled: true) == .syncing)

        status.apply(event(.export, id: id, endsAfter: 4))
        #expect(!status.isSyncing)
        #expect(status.lastSuccessfulSync == start.addingTimeInterval(4))
        #expect(status.summary(isEnabled: true) == .synced(start.addingTimeInterval(4)))
    }

    @Test func setupStartsMirroringButIsNotASync() {
        var status = CloudSyncStatus(account: .available)
        status.apply(event(.setup, endsAfter: 1))

        #expect(status.hasStartedMirroring)
        #expect(status.lastSuccessfulSync == nil)
        #expect(status.summary(isEnabled: true) == .waiting)
    }

    @Test func overlappingEventsStaySyncingUntilAllEnd() {
        let importID = UUID()
        let exportID = UUID()
        var status = CloudSyncStatus(account: .available)
        status.apply(event(.import, id: importID))
        status.apply(event(.export, id: exportID))
        status.apply(event(.import, id: importID, endsAfter: 2))

        #expect(status.isSyncing)
        status.apply(event(.export, id: exportID, endsAfter: 3))
        #expect(!status.isSyncing)
    }

    @Test func failureShowsProblemUntilTheNextSuccess() {
        var status = CloudSyncStatus(account: .available, lastSuccessfulSync: start)
        status.apply(event(.export, endsAfter: 2, succeeded: false, error: CKError(.quotaExceeded)))

        #expect(status.lastProblem == .iCloudFull)
        #expect(status.summary(isEnabled: true) == .problem(.iCloudFull))
        // The last good sync is kept for when the problem clears.
        #expect(status.lastSuccessfulSync == start)

        status.apply(event(.import, endsAfter: 5))
        #expect(status.lastProblem == nil)
        #expect(status.summary(isEnabled: true) == .synced(start.addingTimeInterval(5)))
    }

    @Test func lastSuccessfulSyncNeverMovesBackward() {
        var status = CloudSyncStatus(account: .available, lastSuccessfulSync: start.addingTimeInterval(100))
        status.apply(event(.import, endsAfter: 5))
        #expect(status.lastSuccessfulSync == start.addingTimeInterval(100))
    }

    @Test func accountStatusDecidesSignInAndRestriction() {
        var status = CloudSyncStatus()
        status.apply(account: .noAccount)
        #expect(status.summary(isEnabled: true) == .signInRequired)

        status.apply(account: .restricted)
        #expect(status.summary(isEnabled: true) == .accountRestricted)

        status.apply(event(.export, endsAfter: 1, succeeded: false, error: CKError(.notAuthenticated)))
        status.apply(account: .available)
        // Signing in clears the sign-in error without waiting for a sync.
        #expect(status.lastProblem == nil)
    }

    @Test func offIgnoresEverythingElse() {
        var status = CloudSyncStatus(account: .noAccount)
        status.apply(event(.export))
        #expect(status.summary(isEnabled: false) == .off)
    }

    @Test func reopeningTheStoreDropsEventsThatWillNeverEnd() {
        var status = CloudSyncStatus(account: .available)
        status.apply(event(.setup, endsAfter: 1))
        status.apply(event(.export, endsAfter: 2, succeeded: false, error: CKError(.networkUnavailable)))
        status.apply(event(.export))
        status.storeDidReload()

        #expect(!status.isSyncing)
        #expect(!status.hasStartedMirroring)
        #expect(!status.hasCompletedSetup)
        #expect(status.lastProblem == nil)
    }

    // MARK: Errors in plain words

    @Test func cloudKitErrorsMapToPlainProblems() {
        #expect(CloudSyncProblem(error: CKError(.notAuthenticated)) == .notSignedIn)
        #expect(CloudSyncProblem(error: CKError(.quotaExceeded)) == .iCloudFull)
        #expect(CloudSyncProblem(error: CKError(.networkUnavailable)) == .offline)
        #expect(CloudSyncProblem(error: CKError(.networkFailure)) == .offline)
        #expect(CloudSyncProblem(error: CKError(.serviceUnavailable)) == .iCloudBusy)
        #expect(CloudSyncProblem(error: CKError(.requestRateLimited)) == .iCloudBusy)
        #expect(CloudSyncProblem(error: CKError(.internalError)) == .other)
        #expect(CloudSyncProblem(error: nil) == .other)
    }

    @Test func partialFailureUsesItsSpecificReason() {
        let partial = NSError(
            domain: CKErrorDomain,
            code: CKError.partialFailure.rawValue,
            userInfo: [CKPartialErrorsByItemIDKey: [
                CKRecord.ID(recordName: "a"): NSError(domain: CKErrorDomain, code: CKError.batchRequestFailed.rawValue),
                CKRecord.ID(recordName: "b"): NSError(domain: CKErrorDomain, code: CKError.quotaExceeded.rawValue),
            ]]
        )
        #expect(CloudSyncProblem(error: partial) == .iCloudFull)
    }

    @Test func wrappedCloudKitErrorIsFound() {
        let coreDataError = NSError(
            domain: NSCocoaErrorDomain,
            code: 134_060,
            userInfo: [NSUnderlyingErrorKey: NSError(domain: CKErrorDomain, code: CKError.networkUnavailable.rawValue)]
        )
        #expect(CloudSyncProblem(error: coreDataError) == .offline)
    }

    @Test func setupWithoutAnAccountAsksToSignIn() {
        let noAccount = NSError(domain: NSCocoaErrorDomain, code: CloudSyncProblem.noAccountSetupErrorCode)
        #expect(CloudSyncProblem(error: noAccount) == .notSignedIn)

        var status = CloudSyncStatus()
        status.apply(event(.setup, endsAfter: 1, succeeded: false, error: noAccount))
        #expect(!status.hasCompletedSetup)
        #expect(status.summary(isEnabled: true) == .signInRequired)
    }

    @Test func problemMessagesFitTheErrorBudget() {
        let problems: [CloudSyncProblem] = [.notSignedIn, .iCloudFull, .offline, .iCloudBusy, .other]
        for problem in problems {
            let words = problem.message.split(whereSeparator: \.isWhitespace)
            #expect(words.count <= 15, "\(problem) is \(words.count) words")
            #expect(!problem.message.contains("!"))
            #expect(!words.contains("I"), "Settings never says I")
            #expect(problem.message.hasSuffix("."))
        }
    }

    // MARK: Monitor

    @Test func monitorKeepsTheLastSyncAcrossLaunches() throws {
        let defaults = try #require(UserDefaults(suiteName: "CloudSyncStatusTests-\(UUID().uuidString)"))
        let monitor = CloudSyncMonitor(defaults: defaults)
        monitor.record(event(.export, endsAfter: 3))

        let relaunched = CloudSyncMonitor(defaults: defaults)
        #expect(relaunched.status.lastSuccessfulSync == start.addingTimeInterval(3))
    }

    /// `CKContainer` traps without the iCloud entitlement, so the monitor asks
    /// for the account only once mirroring finished setup.
    @Test func monitorAsksForTheAccountOnlyAfterSetup() async throws {
        let defaults = try #require(UserDefaults(suiteName: "CloudSyncStatusTests-\(UUID().uuidString)"))
        let asked = AsyncCounter()
        let monitor = CloudSyncMonitor(defaults: defaults) {
            await asked.increment()
            return .available
        }

        monitor.refreshAccountStatus()
        let setupID = UUID()
        monitor.record(event(.setup, id: setupID))
        try await Task.sleep(for: .milliseconds(50))
        #expect(await asked.value == 0)
        #expect(monitor.status.account == .unknown)

        monitor.record(event(.setup, id: setupID, endsAfter: 1))
        for _ in 0..<50 where monitor.status.account != .available {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(await asked.value == 1)
        #expect(monitor.status.account == .available)
    }

    @Test func monitorRemembersWhetherAnAccountWasAvailable() throws {
        let defaults = try #require(UserDefaults(suiteName: "CloudSyncStatusTests-\(UUID().uuidString)"))
        let monitor = CloudSyncMonitor(defaults: defaults)

        monitor.apply(account: .available)
        #expect(defaults.bool(forKey: PersistenceStoreConfiguration.lastKnownAccountAvailableKey))

        monitor.apply(account: .unknown)
        #expect(defaults.bool(forKey: PersistenceStoreConfiguration.lastKnownAccountAvailableKey))

        monitor.apply(account: .noAccount)
        #expect(!defaults.bool(forKey: PersistenceStoreConfiguration.lastKnownAccountAvailableKey))
    }

    @Test func liveSwitchLooksStalledOnlyWhenMirroringNeverStarts() throws {
        let defaults = try #require(UserDefaults(suiteName: "CloudSyncStatusTests-\(UUID().uuidString)"))
        let monitor = CloudSyncMonitor(defaults: defaults)
        let requested = Date()
        monitor.noteSwitchApplied(mirroring: true, at: requested)

        #expect(!monitor.mirroringLooksStalled(now: requested.addingTimeInterval(5), after: 20))
        #expect(monitor.mirroringLooksStalled(now: requested.addingTimeInterval(21), after: 20))

        monitor.record(event(.setup))
        #expect(monitor.mirroringStartRequestedAt == nil)
        #expect(!monitor.mirroringLooksStalled(now: requested.addingTimeInterval(60), after: 20))
    }

    @Test func turningSyncOffNeverLooksStalled() throws {
        let defaults = try #require(UserDefaults(suiteName: "CloudSyncStatusTests-\(UUID().uuidString)"))
        let monitor = CloudSyncMonitor(defaults: defaults)
        let requested = Date()
        monitor.noteSwitchApplied(mirroring: false, at: requested)
        #expect(!monitor.mirroringLooksStalled(now: requested.addingTimeInterval(60), after: 20))
        #expect(monitor.takeScrollTarget() == "icloud")
        #expect(monitor.takeScrollTarget() == nil)
    }
}

private actor AsyncCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}
