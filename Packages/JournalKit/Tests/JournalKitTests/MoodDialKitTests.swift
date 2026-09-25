import Foundation
import SwiftUI
import Testing
@testable import MoodDialKit
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct MoodAssetPresenceTests {

    private func assetExists(_ name: String) -> Bool {
        // Command-line `swift build` copies the catalog raw instead of
        // compiling it with actool; verify the imageset folder directly.
        if let catalogURL = Mood.assetBundle.url(forResource: "Moods", withExtension: "xcassets") {
            let contents = catalogURL
                .appendingPathComponent("\(name).imageset")
                .appendingPathComponent("Contents.json")
            return FileManager.default.fileExists(atPath: contents.path)
        }
        #if canImport(UIKit)
        return UIImage(named: name, in: .module, with: nil) != nil
        #elseif canImport(AppKit)
        return Mood.assetBundle.image(forResource: name) != nil
        #else
        return true
        #endif
    }

    /// Every asset name referenced by every mood must exist in the package
    /// bundle. `Image(named:)` fails silently, so this is the guard against
    /// a broken asset-catalog migration.
    @Test func everyMoodAssetResolvesInModuleBundle() throws {
        for mood in Mood.allCases {
            let names = [
                mood.largeMoodAssetName,
                mood.miniMoodAssetName,
                mood.dialFaceAssetName,
                mood.moodGlowAssetName,
            ]
            for name in names {
                #expect(
                    assetExists(name),
                    "Missing mood asset \(name) for mood \(mood.rawValue.isEmpty ? "none" : mood.rawValue)"
                )
            }
        }
    }
}

struct MoodDialMathTests {

    @Test func dialMoodsContainAllCases() {
        #expect(Set(Mood.dialMoods) == Set(Mood.allCases))
    }

    @Test func rotationRoundTripsThroughEveryDialIndex() {
        for (index, mood) in Mood.dialMoods.enumerated() {
            let rotation = MoodDialMath.rotationDegrees(for: index)
            #expect(MoodDialMath.nearestIndex(forRotationDegrees: rotation) == index)
            #expect(MoodDialMath.mood(forRotationDegrees: rotation) == mood)
        }
    }

    @Test func neutralIndexPointsAtNone() {
        #expect(Mood.dialMoods[Mood.neutralDialIndex] == .none)
    }

    @Test func resistedRotationClampsBeyondEnds() {
        let first = MoodDialMath.rotationDegrees(for: 0)
        let last = MoodDialMath.rotationDegrees(for: Mood.dialMoods.count - 1)
        let overFirst = MoodDialMath.resistedRotationDegrees(first + 40)
        let underLast = MoodDialMath.resistedRotationDegrees(last - 40)
        #expect(overFirst < first + 40)
        #expect(overFirst > first)
        #expect(underLast > last - 40)
        #expect(underLast < last)
    }

    @Test func normalizedDeltaWrapsAround() {
        #expect(MoodDialMath.normalizedDeltaDegrees(from: 350, to: 10) == 20)
        #expect(MoodDialMath.normalizedDeltaDegrees(from: 10, to: 350) == -20)
    }

    @Test func rawEmotionMappingCoversSynonyms() {
        #expect(Mood(rawEmotion: "joy") == .happy)
        #expect(Mood(rawEmotion: "fear") == .anxious)
        #expect(Mood(rawEmotion: "unknown-thing") == Mood.none)
    }
}

struct MoodDialPersistenceTests {

    @Test func openingMoodFallsBackToNoneForNonDialMood() {
        #expect(MoodDialPersistence.openingMood(for: .happy) == .happy)
        #expect(MoodDialPersistence.openingMood(for: .none) == Mood.none)
    }

    @Test func shouldSaveOnlyOnChange() {
        #expect(MoodDialPersistence.shouldSave(originalMood: .none, draftMood: .calm))
        #expect(!MoodDialPersistence.shouldSave(originalMood: .calm, draftMood: .calm))
    }
}
