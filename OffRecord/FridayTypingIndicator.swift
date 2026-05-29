//
//  FridayTypingIndicator.swift
//  OffRecord
//
//  Subtle Friday thinking indicator.
//

import SwiftUI

struct FridayTypingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAnimating = false

    var body: some View {
        HStack(alignment: .bottom, spacing: OffRecordSpacing.md) {
            FridayMascotView(pose: .thinking, size: 40)
                .accessibilityHidden(true)

            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(OffRecordColor.textLavender)
                        .frame(width: 7, height: 7)
                        .opacity(dotOpacity(for: index))
                        .scaleEffect(dotScale(for: index))
                        .animation(
                            reduceMotion ? nil : .easeInOut(duration: 0.7).repeatForever().delay(Double(index) * 0.16),
                            value: isAnimating
                        )
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(OffRecordColor.backgroundLavenderTint, in: Capsule())
            .overlay {
                Capsule().stroke(OffRecordColor.borderSoft, lineWidth: 1)
            }
            .accessibilityLabel("Friday is thinking")

            Spacer(minLength: 0)
        }
        .onAppear {
            isAnimating = true
        }
    }

    private func dotOpacity(for index: Int) -> Double {
        guard !reduceMotion else { return 0.75 }
        return isAnimating ? 0.45 + Double(index) * 0.18 : 0.65
    }

    private func dotScale(for index: Int) -> CGFloat {
        guard !reduceMotion else { return 1 }
        return isAnimating ? 0.86 + CGFloat(index) * 0.08 : 1
    }
}
