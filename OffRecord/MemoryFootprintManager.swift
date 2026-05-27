import CoreData
import Foundation
import os.log

#if os(iOS)
import UIKit
#endif

private let memoryLogger = Logger(subsystem: "com.singularity.offrecord", category: "Memory")

final class MemoryFootprintManager {
    static let shared = MemoryFootprintManager()

    private weak var viewContext: NSManagedObjectContext?
    private var didConfigure = false

    private init() {}

    func configure(viewContext: NSManagedObjectContext) {
        self.viewContext = viewContext
        guard !didConfigure else { return }
        didConfigure = true

        #if os(iOS)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
        #endif
    }

    func prepareForBackground() {
        NotificationCenter.default.post(name: .offRecordWillReleaseTransientMemory, object: nil)

        DispatchQueue.main.async { [weak self] in
            self?.releaseTransientMemory(reason: "background")
        }
    }

    func releaseTransientMemory(reason: String) {
        memoryLogger.info("Releasing transient memory reason=\(reason, privacy: .public)")
        FridaySpriteMemoryCache.clear()
        MoodDialWheelGeometryCache.clear()
        URLCache.shared.removeAllCachedResponses()
        viewContext?.refreshAllObjects()
    }

    #if os(iOS)
    @objc private func handleMemoryWarning() {
        releaseTransientMemory(reason: "memory-warning")
    }
    #endif
}

extension Notification.Name {
    static let offRecordWillReleaseTransientMemory = Notification.Name("offRecordWillReleaseTransientMemory")
}
