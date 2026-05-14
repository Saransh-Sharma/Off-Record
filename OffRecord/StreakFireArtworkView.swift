//
//  StreakFireArtworkView.swift
//  OffRecord
//
//  Decorative fire artwork for active and inactive streak states.
//

import SwiftUI

struct StreakFireArtworkView: View {
    let imageName: String
    let size: CGFloat
    let accentFill: Color
    let isActive: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(accentFill.opacity(isActive ? 0.16 : 0.10))
                .frame(width: size * 0.92, height: size * 0.92)

            Image(imageName)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size, height: size)
                .shadow(
                    color: isActive ? OffRecordColor.brandCoral.opacity(0.24) : .clear,
                    radius: 18,
                    x: 0,
                    y: 10
                )
                .accessibilityHidden(true)
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
    }
}

#Preview {
    StreakFireArtworkView(
        imageName: "StreakFire",
        size: 118,
        accentFill: OffRecordColor.brandPeach,
        isActive: true
    )
    .padding()
}
