//
//  PrivacyProofStep.swift
//  OffRecord
//
//  Onboarding step 3: where the journal lives, and that Friday is AI.
//

import SwiftUI

struct PrivacyProofStep: View {
    var body: some View {
        OnboardingQuestion(
            subtitle: String(localized: "Nothing leaves your \(DeviceNoun.current) unless you export it or turn on iCloud."),
            contentSpacing: 16
        ) {
            VStack(spacing: 10) {
                PrivacyProofRow(icon: "person.crop.circle.badge.xmark", title: String(localized: "No account"), detail: String(localized: "Open the app and start."))
                PrivacyProofRow(icon: "server.rack", title: String(localized: "No OffRecord servers"), detail: String(localized: "Transcription and Friday run on your \(DeviceNoun.current)."))
                PrivacyProofRow(icon: "chart.bar.xaxis", title: String(localized: "No ads or tracking"), detail: String(localized: "Nothing you write is used for ads."))
                PrivacyProofRow(icon: "sparkles", title: String(localized: "Friday is AI"), detail: String(localized: "She can be wrong, and she isn’t a therapist."))
            }
        }
    }
}

private struct PrivacyProofRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(OffRecordTypography.sectionTitle)
                .foregroundStyle(OnboardingPalette.foreground)
                .frame(width: 34, height: 34)
                .background(OnboardingPalette.surfaceSubtle)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(OffRecordTypography.sectionTitle)
                    .foregroundStyle(OnboardingPalette.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(OffRecordTypography.bodyMedium)
                    .foregroundStyle(OnboardingPalette.secondaryForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OnboardingPalette.surfaceSoft)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
