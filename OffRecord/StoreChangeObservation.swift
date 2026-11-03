//
//  StoreChangeObservation.swift
//  OffRecord
//
//  Calls back on the main actor when a store's contexts save or iCloud
//  changes it. The observers run on the posting thread and hand off to main
//  without waiting. With `queue: .main`, a background save would wait for the
//  main thread, and anything holding main while it waits on that context
//  deadlocks the app.
//

import CoreData
import Foundation

enum StoreChangeObservation {
    static func observe(
        _ coordinator: NSPersistentStoreCoordinator,
        center: NotificationCenter = .default,
        onChange: @escaping @MainActor @Sendable () -> Void
    ) -> [NSObjectProtocol] {
        let notify: @Sendable () -> Void = {
            Task { @MainActor in onChange() }
        }
        return [
            center.addObserver(forName: .NSManagedObjectContextDidSave, object: nil, queue: nil) { note in
                guard let context = note.object as? NSManagedObjectContext,
                      context.persistentStoreCoordinator === coordinator else { return }
                notify()
            },
            center.addObserver(forName: .NSPersistentStoreRemoteChange, object: coordinator, queue: nil) { _ in
                notify()
            }
        ]
    }
}
