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

    var frames: [FridaySpriteFrame] {
        switch self {
        case .idle:
            return [
                .init(column: 0, row: 0),
                .init(column: 0, row: 0),
                .init(column: 1, row: 0),
                .init(column: 0, row: 0)
            ]
        case .wave:
            return [
                .init(column: 0, row: 3),
                .init(column: 1, row: 3),
                .init(column: 2, row: 3),
                .init(column: 1, row: 3)
            ]
        case .listening:
            return [
                .init(column: 0, row: 0),
                .init(column: 1, row: 0)
            ]
        case .thinking:
            return [
                .init(column: 4, row: 5),
                .init(column: 5, row: 5)
            ]
        case .walking:
            return [
                .init(column: 0, row: 4),
                .init(column: 1, row: 4),
                .init(column: 2, row: 4),
                .init(column: 3, row: 4)
            ]
        case .confiding:
            return [
                .init(column: 0, row: 5),
                .init(column: 1, row: 5),
                .init(column: 2, row: 5)
            ]
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

struct FridaySpriteFrame: Hashable {
    static let width = 256
    static let height = 208

    let column: Int
    let row: Int
}

struct FridayMascotView: View {
    let pose: FridayMascotPose
    var size: CGFloat = 96
    var animationSpeed: TimeInterval = 0.55

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var frameIndex = 0

    private var frames: [FridaySpriteFrame] { pose.frames }
    private var currentFrame: FridaySpriteFrame {
        reduceMotion ? frames[0] : frames[frameIndex % frames.count]
    }

    var body: some View {
        FridaySpriteImage(frame: currentFrame)
            .interpolation(.none)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityLabel(pose.accessibilityLabel)
            .onAppear {
                guard !reduceMotion, frames.count > 1 else { return }
                frameIndex = 0
            }
            .task(id: pose) {
                guard !reduceMotion, frames.count > 1 else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: UInt64(animationSpeed * 1_000_000_000))
                    frameIndex = (frameIndex + 1) % frames.count
                }
            }
    }
}

private struct FridaySpriteImage: View {
    let frame: FridaySpriteFrame

    var body: some View {
        if let image = FridaySpriteCache.image(for: frame) {
            Image(uiImage: image)
                .resizable()
        } else {
            Image(systemName: "sparkles")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
        }
    }
}

private enum FridaySpriteCache {
    private static var cache: [FridaySpriteFrame: UIImage] = [:]

    static func image(for frame: FridaySpriteFrame) -> UIImage? {
        if let cached = cache[frame] { return cached }
        guard let source = UIImage(named: "FridaySpritesheet"),
              let cgImage = source.cgImage else {
            return nil
        }

        let cropRect = CGRect(
            x: frame.column * FridaySpriteFrame.width,
            y: frame.row * FridaySpriteFrame.height,
            width: FridaySpriteFrame.width,
            height: FridaySpriteFrame.height
        )
        guard let cropped = cgImage.cropping(to: cropRect) else { return nil }
        let image = UIImage(cgImage: cropped, scale: source.scale, orientation: source.imageOrientation)
        cache[frame] = image
        return image
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
