//
//  IntentStep.swift
//  OffRecord
//
//  Onboarding step 2: what brings you here, as a checklist of reasons.
//

import SwiftUI

struct IntentStep: View {
    @Binding var selectedIntents: Set<OnboardingPainPoint>

    var body: some View {
        OnboardingQuestion(
            subtitle: String(localized: "Choose any."),
            contentSpacing: 18
        ) {
            VStack(spacing: 10) {
                ForEach(OnboardingPainPoint.allCases) { pain in
                    ChoiceRow(
                        title: pain.title,
                        icon: pain.icon,
                        isSelected: selectedIntents.contains(pain),
                        style: .checkbox
                    ) {
                        if selectedIntents.contains(pain) {
                            selectedIntents.remove(pain)
                        } else {
                            selectedIntents.insert(pain)
                        }
                    }
                }
            }
        }
    }
}

private enum ChoiceRowStyle {
    case radio
    case checkbox
}

private struct ChoiceRow: View {
    let title: String
    let icon: String
    let isSelected: Bool
    var style: ChoiceRowStyle = .radio
    let action: () -> Void

    var body: some View {
        Button {
            HapticManager.shared.selectionChanged()
            action()
        } label: {
            OnboardingSelectableContainer(isSelected: isSelected) {
                HStack(spacing: 14) {
                    Image(systemName: icon)
                        .font(OffRecordTypography.sectionTitle)
                        .frame(width: 34, height: 34)
                        .foregroundStyle(OnboardingPalette.foreground)
                        .background(isSelected ? OnboardingPalette.surfaceSoft : OnboardingPalette.surfaceSubtle)
                        .clipShape(Circle())

                    Text(title)
                        .font(isSelected ? OffRecordTypography.sectionTitle : OffRecordTypography.labelLarge)
                        .foregroundStyle(OnboardingPalette.foreground)
                        .lineLimit(2)
                        .minimumScaleFactor(0.86)
                        .multilineTextAlignment(.leading)
                        .layoutPriority(1)

                    Spacer()

                    Image(systemName: selectedIconName)
                        .font(OffRecordTypography.sectionTitle)
                        .foregroundStyle(isSelected ? OnboardingPalette.foreground : OnboardingPalette.tertiaryForeground)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var selectedIconName: String {
        switch style {
        case .radio:
            return isSelected ? "checkmark.circle.fill" : "circle"
        case .checkbox:
            return isSelected ? "checkmark.square.fill" : "square"
        }
    }
}
