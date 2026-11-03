import CoreData
import Foundation
import Testing
@testable import OffRecord

/// A background save must never wait for the main thread. If it does, any
/// code that holds the main thread while waiting on that context deadlocks
/// the app (RocketSim Connect did this under Xcode's debugger, freezing launch
/// on the splash screen).
@MainActor
@Suite(.serialized)
struct StoreChangeObservationTests {

    @Test func backgroundSaveDoesNotWaitForTheMainThread() throws {
        let container = PersistenceController(inMemory: true).container
        let background = container.newBackgroundContext()
        let saved = DispatchSemaphore(value: 0)

        background.perform {
            Self.insertEntry(in: background)
            try? background.save()
            saved.signal()
        }

        // Hold the main thread until the save finishes, as the debugger tool did.
        #expect(saved.wait(timeout: .now() + 3) == .success)
    }

    @Test func notifiesOnMainForItsOwnStoreOnly() async throws {
        let container = PersistenceController(inMemory: true).container
        let otherContainer = PersistenceController(inMemory: true).container
        let changes = ChangeCounter()
        let observers = StoreChangeObservation.observe(container.persistentStoreCoordinator) {
            changes.count += 1
        }
        defer { observers.forEach(NotificationCenter.default.removeObserver) }

        let other = otherContainer.newBackgroundContext()
        try await other.perform {
            Self.insertEntry(in: other)
            try other.save()
        }
        let background = container.newBackgroundContext()
        try await background.perform {
            Self.insertEntry(in: background)
            try background.save()
        }

        for _ in 0..<100 where changes.count == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        try await Task.sleep(for: .milliseconds(50))
        #expect(changes.count == 1)
    }

    private nonisolated static func insertEntry(in context: NSManagedObjectContext) {
        let entry = DiaryEntry(context: context)
        entry.id = UUID()
        entry.date = Date()
        entry.updatedAt = Date()
        entry.text = "Walked by the river."
    }
}

@MainActor
private final class ChangeCounter {
    var count = 0
}
