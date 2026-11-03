//
//  WelcomeStep.swift
//  OffRecord
//
//  Onboarding step 1: Friday waves hello and asks for an optional name.
//

import SwiftUI

// MARK: - Steps

struct WelcomeStep: View {
    @Binding var nameDraft: String
    let isCompact: Bool

    var body: some View {
        VStack(alignment: .center, spacing: isCompact ? 18 : 24) {
            if !isCompact {
                ZStack {
                    Circle()
                        .fill(OnboardingPalette.surfaceSubtle)
                        .frame(width: 196, height: 196)
                    FridayMascotView(pose: .wave, size: 146)
                }
                .accessibilityHidden(true)
            }

            Text("Talk or type. It all stays on your \(DeviceNoun.current).")
                .font(OffRecordTypography.bodyMedium)
                .foregroundStyle(OnboardingPalette.secondaryForeground)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            OnboardingNameField(text: $nameDraft)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .id(OnboardingScrollTarget.welcomeNameField)
        }
    }
}
