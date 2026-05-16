import Foundation

#if canImport(UIKit)
import UIKit

enum MoodAssetPreheater {
    private static let lock = NSLock()
    private static var didPreheat = false
    private static let queue = DispatchQueue(label: "com.singularity.offrecord.mood-preheater", qos: .userInitiated)

    static func preheatMoodAssets() {
        lock.lock()
        let shouldPreheat = !didPreheat
        didPreheat = true
        lock.unlock()

        guard shouldPreheat else { return }

        PerformanceSignposts.event("MoodAssetPreheatScheduled")
        let assetNames = Set(
            Mood.dialMoods.flatMap { mood in
                [mood.dialFaceAssetName, mood.largeMoodAssetName, mood.moodGlowAssetName]
            }
        )

        queue.async {
            let token = PerformanceSignposts.begin("MoodAssetPreheat")
            for name in assetNames {
                autoreleasepool {
                    _ = UIImage(named: name)?.preparingForDisplay()
                }
            }
            PerformanceSignposts.end(token)
        }
    }

    #if DEBUG
    static func resetForTesting() {
        lock.lock()
        didPreheat = false
        lock.unlock()
    }
    #endif
}
#else
enum MoodAssetPreheater {
    static func preheatMoodAssets() {}
}
#endif
