//
//  CloudSyncStatus.swift
//  OffRecord
//
//  What iCloud Sync is doing, reduced from NSPersistentCloudKitContainer
//  events and the iCloud account status. Pure values, so tests can feed it
//  synthetic events (`NSPersistentCloudKitContainer.Event` has no public init).
//

import CloudKit
import CoreData
import Foundation

/// One sync event, copied out of `NSPersistentCloudKitContainer.Event`.
struct CloudSyncEvent: Equatable {
    enum Kind: Equatable {
        case setup
        case `import`
        case export
    }

    let id: UUID
    let kind: Kind
    let startDate: Date
    /// Nil while the event is still running.
    let endDate: Date?
    let succeeded: Bool
    let problem: CloudSyncProblem?

    init(id: UUID, kind: Kind, startDate: Date, endDate: Date?, succeeded: Bool, problem: CloudSyncProblem?) {
        self.id = id
        self.kind = kind
        self.startDate = startDate
        self.endDate = endDate
        self.succeeded = succeeded
        self.problem = problem
    }

    init?(_ event: NSPersistentCloudKitContainer.Event) {
        let kind: Kind
        switch event.type {
        case .setup: kind = .setup
        case .import: kind = .import
        case .export: kind = .export
        @unknown default: return nil
        }
        self.init(
            id: event.identifier,
            kind: kind,
            startDate: event.startDate,
            endDate: event.endDate,
            succeeded: event.succeeded,
            problem: event.endDate != nil && !event.succeeded ? CloudSyncProblem(error: event.error) : nil
        )
    }
}

/// The iCloud account, as `CKContainer.accountStatus` reports it.
enum CloudAccountState: Equatable {
    case unknown
    case available
    case noAccount
    case restricted
    case temporarilyUnavailable

    init(_ status: CKAccountStatus) {
        switch status {
        case .available: self = .available
        case .noAccount: self = .noAccount
        case .restricted: self = .restricted
        case .temporarilyUnavailable: self = .temporarilyUnavailable
        case .couldNotDetermine: self = .unknown
        @unknown default: self = .unknown
        }
    }
}

/// A sync failure in plain words. Each case maps to one message that says what to do.
enum CloudSyncProblem: Equatable {
    case notSignedIn
    case iCloudFull
    case offline
    case iCloudBusy
    case other

    init(error: Error?) {
        guard let error else {
            self = .other
            return
        }
        let nsError = error as NSError
        // A partial failure wraps the real reasons; use the first one that says more.
        if nsError.domain == CKErrorDomain,
           nsError.code == CKError.partialFailure.rawValue,
           let partial = nsError.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error],
           let specific = partial.values.lazy.map(CloudSyncProblem.init(error:)).first(where: { $0 != .other }) {
            self = specific
            return
        }
        if nsError.domain == CKErrorDomain, let code = CKError.Code(rawValue: nsError.code) {
            switch code {
            case .notAuthenticated, .accountTemporarilyUnavailable:
                self = .notSignedIn
            case .quotaExceeded:
                self = .iCloudFull
            case .networkUnavailable, .networkFailure:
                self = .offline
            case .serviceUnavailable, .requestRateLimited, .zoneBusy, .serverResponseLost:
                self = .iCloudBusy
            default:
                self = .other
            }
            return
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            self = CloudSyncProblem(error: underlying)
            return
        }
        self = .other
    }

    /// One sentence, at most 15 words, that says what to do next.
    var message: String {
        switch self {
        case .notSignedIn:
            return String(localized: "Sign in to iCloud to sync.", comment: "iCloud Sync error")
        case .iCloudFull:
            return String(localized: "Free up iCloud storage to keep syncing.", comment: "iCloud Sync error: iCloud storage is full")
        case .offline:
            return String(localized: "Connect to the internet to sync.", comment: "iCloud Sync error")
        case .iCloudBusy:
            return String(localized: "OffRecord will try again when iCloud responds.", comment: "iCloud Sync error: iCloud servers are busy")
        case .other:
            return String(localized: "OffRecord will try again soon.", comment: "iCloud Sync error with no specific cause")
        }
    }
}

/// Everything the iCloud card shows, reduced from events and the account status.
struct CloudSyncStatus: Equatable {
    var account: CloudAccountState = .unknown
    /// When the last import or export finished without an error.
    var lastSuccessfulSync: Date?
    /// The last setup, import, or export that ended in an error. A later success clears it.
    var lastProblem: CloudSyncProblem?
    /// Whether this process has seen mirroring start (a setup event).
    var hasStartedMirroring = false
    /// Events that started and haven't finished.
    private(set) var runningEventIDs: Set<UUID> = []

    var isSyncing: Bool { !runningEventIDs.isEmpty }

    init(account: CloudAccountState = .unknown, lastSuccessfulSync: Date? = nil) {
        self.account = account
        self.lastSuccessfulSync = lastSuccessfulSync
    }

    mutating func apply(_ event: CloudSyncEvent) {
        if event.kind == .setup {
            hasStartedMirroring = true
        }
        guard let endDate = event.endDate else {
            runningEventIDs.insert(event.id)
            return
        }
        runningEventIDs.remove(event.id)
        if event.succeeded {
            if event.kind != .setup {
                lastSuccessfulSync = max(lastSuccessfulSync ?? .distantPast, endDate)
            }
            lastProblem = nil
        } else {
            lastProblem = event.problem ?? .other
        }
    }

    mutating func apply(account: CloudAccountState) {
        self.account = account
        if account == .available, lastProblem == .notSignedIn {
            lastProblem = nil
        }
    }

    /// Clears running events when the store reopens; the old store's events never finish.
    mutating func storeDidReload() {
        runningEventIDs.removeAll()
        hasStartedMirroring = false
    }

    /// What the card's subtitle and status rows say.
    enum Summary: Equatable {
        case off
        case signInRequired
        case accountRestricted
        case syncing
        case problem(CloudSyncProblem)
        case synced(Date)
        case waiting
    }

    func summary(isEnabled: Bool) -> Summary {
        guard isEnabled else { return .off }
        switch account {
        case .noAccount: return .signInRequired
        case .restricted: return .accountRestricted
        default: break
        }
        if isSyncing { return .syncing }
        if let lastProblem { return .problem(lastProblem) }
        if let lastSuccessfulSync { return .synced(lastSuccessfulSync) }
        return .waiting
    }
}
