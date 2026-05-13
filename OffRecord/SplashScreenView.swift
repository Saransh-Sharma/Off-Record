//
//  SplashScreenView.swift
//  OffRecord
//
//  Lightweight launch overlay for the OffRecord app icon animation.
//

import SwiftUI

struct SplashScreenView: View {
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var iconScale: CGFloat = 1
    @State private var overlayOpacity: Double = 1
    @State private var hasStarted = false

    var body: some View {
        GeometryReader { proxy in
            let iconSize = iconSize(for: proxy.size)
            let targetScale = targetScale(for: proxy.size, iconSize: iconSize)

            ZStack {
                OffRecordColor.appBackgroundGradient
                    .ignoresSafeArea()

                Image("SplashIcon")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: iconSize, height: iconSize)
                    .clipped()
                    .scaleEffect(iconScale)
            }
            .opacity(overlayOpacity)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .onAppear {
                startAnimation(targetScale: targetScale)
            }
        }
    }

    private func iconSize(for size: CGSize) -> CGFloat {
        min(max(min(size.width, size.height) * 0.24, 96), 148)
    }

    private func targetScale(for size: CGSize, iconSize: CGFloat) -> CGFloat {
        (max(size.width, size.height) / iconSize) * 1.25
    }

    private func startAnimation(targetScale: CGFloat) {
        guard !hasStarted else { return }
        hasStarted = true

        if reduceMotion {
            withAnimation(.easeOut(duration: 0.18), completionCriteria: .logicallyComplete) {
                iconScale = 1.08
                overlayOpacity = 0
            } completion: {
                onFinished()
            }
            return
        }

        withAnimation(.easeInOut(duration: 0.7), completionCriteria: .logicallyComplete) {
            iconScale = targetScale
        } completion: {
            withAnimation(.easeOut(duration: 0.18), completionCriteria: .logicallyComplete) {
                overlayOpacity = 0
            } completion: {
                onFinished()
            }
        }
    }
}

#Preview {
    SplashScreenView {}
}
