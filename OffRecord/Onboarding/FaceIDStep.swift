//
//  FaceIDStep.swift
//  OffRecord
//
//  Onboarding step 4: lock the journal with Face ID, Touch ID, Optic ID, or
//  the passcode.
//

import SwiftUI

struct FaceIDStep: View {
    let biometryName: String
    let isEnabled: Bool
    let isAvailable: Bool

    var body: some View {
        OnboardingQuestion(
            subtitle: isPasscode
                ? String(localized: "Require your passcode to open OffRecord.")
                : String(localized: "Require \(biometryName) to open OffRecord.", comment: "The placeholder is Face ID, Touch ID, or Optic ID"),
            contentSpacing: 18
        ) {
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(OffRecordColor.backgroundSageTint.opacity(0.28))
                        .frame(width: 132, height: 132)
                    Image(systemName: isEnabled ? "checkmark.shield.fill" : lockIcon)
                        .font(.system(.largeTitle, weight: .semibold)).imageScale(.large)
                        .foregroundStyle(OnboardingPalette.foreground)
                }

                VStack(alignment: .leading, spacing: 12) {
                    BenefitRow(icon: "lock.fill", text: String(localized: "Locks again when you leave the app."))
                }

                if !isAvailable {
                    Text(unavailableMessage)
                        .font(OffRecordTypography.metadata)
                        .foregroundStyle(OnboardingPalette.secondaryForeground)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding()
                        .background(OnboardingPalette.surfaceSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
    }

    /// "Face ID" reads as a name; a bare "Passcode" doesn't, so it gets its own sentences.
    /// AppLockManager returns the localized "Passcode", so compare against the same key.
    private var isPasscode: Bool {
        biometryName == String(localized: "Passcode")
    }

    private var unavailableMessage: String {
        isPasscode
            ? String(localized: "OffRecord will use your passcode.")
            : String(localized: "\(biometryName) isn’t set up. Your passcode will be used instead.")
    }

    private var lockIcon: String {
        switch biometryName {
        case "Face ID":
            return "faceid"
        case "Touch ID":
            return "touchid"
        default:
            return "lock.shield.fill"
        }
    }
}

private struct BenefitRow: View {
    let icon: String?
    let mood: Mood?
    let text: String

    init(icon: String, text: String) {
        self.icon = icon
        self.mood = nil
        self.text = text
    }

    init(mood: Mood, text: String) {
        self.icon = nil
        self.mood = mood
        self.text = text
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let mood {
                MiniMoodIcon(mood: mood, size: 18, opacity: 0.88)
                    .frame(width: 22)
            } else if let icon {
                Image(systemName: icon)
                    .font(OffRecordTypography.labelMedium)
                    .foregroundStyle(OnboardingPalette.foreground)
                    .frame(width: 22)
            }
            Text(text)
                .font(OffRecordTypography.labelMedium)
                .foregroundStyle(OnboardingPalette.secondaryForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
