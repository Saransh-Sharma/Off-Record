//
//  FridayMascotView.swift
//  OffRecord
//
//  Sprite-based mascot view for Friday, the private AI assistant.
//

import SwiftUI
import UIKit

enum FridayMascotPose {
    case idle
    case wave
    case listening
    case thinking
    case walking
    case confiding

    fileprivate var animation: FridayMascotAnimation {
        switch self {
        case .idle:
            return .idle
        case .wave:
            return .waving
        case .listening, .thinking:
            return .waiting
        case .walking:
            return .running
        case .confiding:
            return .review
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .idle: return "Friday"
        case .wave: return "Friday waving"
        case .listening: return "Friday listening"
        case .thinking: return "Friday thinking"
        case .walking: return "Friday walking"
        case .confiding: return "Friday sitting with you"
        }
    }
}

fileprivate enum FridayMascotAnimation: CaseIterable, Hashable {
    case idle
    case runRight
    case runLeft
    case waving
    case jumping
    case failed
    case waiting
    case running
    case review

    static let frameDuration: TimeInterval = 0.13

    var rowIndex: Int {
        switch self {
        case .idle: return 0
        case .runRight: return 1
        case .runLeft: return 2
        case .waving: return 3
        case .jumping: return 4
        case .failed: return 5
        case .waiting: return 6
        case .running: return 7
        case .review: return 8
        }
    }

    var frameCount: Int {
        switch self {
        case .idle: return 6
        case .runRight, .runLeft: return 8
        case .waving: return 4
        case .jumping: return 5
        case .failed: return 8
        case .waiting, .running, .review: return 6
        }
    }
}

private struct FridaySpriteFrame: Hashable {
    let animation: FridayMascotAnimation
    let index: Int
}

struct FridayMascotView: View {
    let pose: FridayMascotPose
    var size: CGFloat = 96
    var animationSpeed: TimeInterval = FridayMascotAnimation.frameDuration

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion || pose.animation.frameCount <= 1 {
                FridaySpriteImage(frame: FridaySpriteFrame(animation: pose.animation, index: 0))
            } else {
                SwiftUI.TimelineView(.periodic(from: .now, by: max(0.01, animationSpeed))) { timeline in
                    FridaySpriteImage(frame: FridaySpriteFrame(
                        animation: pose.animation,
                        index: frameIndex(for: timeline.date, animation: pose.animation)
                    ))
                }
            }
        }
        .scaledToFit()
        .frame(width: size, height: size)
        .accessibilityLabel(pose.accessibilityLabel)
    }

    private func frameIndex(for date: Date, animation: FridayMascotAnimation) -> Int {
        let duration = max(0.01, animationSpeed)
        let tick = Int(date.timeIntervalSinceReferenceDate / duration)
        return tick % animation.frameCount
    }
}

private struct FridaySpriteImage: View {
    let frame: FridaySpriteFrame

    var body: some View {
        if let image = FridaySpriteCache.image(for: frame) {
            Image(uiImage: image)
                .resizable()
                .interpolation(.none)
                .antialiased(false)
        } else {
            Image(systemName: "sparkles")
                .resizable()
                .scaledToFit()
                .foregroundStyle(OffRecordColor.textLavender)
        }
    }
}

private final class FridaySpriteCache {
    static let shared = FridaySpriteCache()

    private static let cellWidth = 192
    private static let cellHeight = 208

    private var sheetCache: CGImage?
    private var frameCache: [FridaySpriteFrame: UIImage] = [:]
    private let lock = NSLock()

    static func image(for frame: FridaySpriteFrame) -> UIImage? {
        shared.image(for: frame)
    }

    private func image(for frame: FridaySpriteFrame) -> UIImage? {
        lock.lock()
        if let cached = frameCache[frame] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        guard let sheet = sheet() else { return nil }

        let clampedIndex = max(0, min(frame.index, frame.animation.frameCount - 1))

        let cropRect = CGRect(
            x: clampedIndex * Self.cellWidth,
            y: frame.animation.rowIndex * Self.cellHeight,
            width: Self.cellWidth,
            height: Self.cellHeight
        )
        guard let cropped = sheet.cropping(to: cropRect) else { return nil }
        let image = UIImage(cgImage: cropped, scale: UIScreen.main.scale, orientation: .up)

        lock.lock()
        frameCache[frame] = image
        lock.unlock()
        return image
    }

    private func sheet() -> CGImage? {
        lock.lock()
        if let sheetCache {
            lock.unlock()
            return sheetCache
        }
        lock.unlock()

        let decodedSheet: CGImage?
        if let url = Bundle.main.url(forResource: "spritesheet", withExtension: "webp", subdirectory: "Friday AI"),
           let data = try? Data(contentsOf: url),
           let image = UIImage(data: data)?.cgImage {
            decodedSheet = image
        } else {
            decodedSheet = UIImage(named: "FridaySpritesheet")?.cgImage
        }

        guard let decodedSheet else { return nil }

        lock.lock()
        sheetCache = decodedSheet
        lock.unlock()
        return decodedSheet
    }
}

#Preview {
    HStack {
        FridayMascotView(pose: .idle)
        FridayMascotView(pose: .wave)
        FridayMascotView(pose: .thinking)
        FridayMascotView(pose: .confiding)
    }
    .padding()
}
