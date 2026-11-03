//
//  OnboardingComponents.swift
//  OffRecord
//
//  Pieces the onboarding steps share: the palette for the pastel pages, the
//  scroll anchors for the text fields, the selectable card, and the subtitle
//  and content layout every step uses.
//

import SwiftUI

// MARK: - Components

enum OnboardingScrollTarget {
    static let welcomeNameField = "onboarding.welcome.nameField.anchor"
    static let firstEntryTextField = "onboarding.firstEntry.textField.anchor"
}

enum OnboardingPalette {
    static let foreground = OffRecordColor.textBrand
    static let secondaryForeground = OffRecordColor.textBrand.opacity(0.74)
    static let tertiaryForeground = OffRecordColor.textBrand.opacity(0.54)
    static let surface = OffRecordColor.surfacePrimary
    static let surfaceSoft = OffRecordColor.surfacePrimary.opacity(0.72)
    static let surfaceSubtle = OffRecordColor.surfacePrimary.opacity(0.28)
    static let surfaceBarelyVisible = OffRecordColor.surfacePrimary.opacity(0.16)
    static let border = OffRecordColor.textBrand.opacity(0.14)
    static let selectedBorder = OffRecordColor.textBrand.opacity(0.78)
}

struct OnboardingSelectableContainer<Content: View>: View {
    let isSelected: Bool
    var cornerRadius: CGFloat = 18
    var padding: CGFloat = 14
    let content: Content

    init(
        isSelected: Bool,
        cornerRadius: CGFloat = 18,
        padding: CGFloat = 14,
        @ViewBuilder content: () -> Content
    ) {
        self.isSelected = isSelected
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(isSelected ? OnboardingPalette.surface : OnboardingPalette.surfaceSubtle)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(isSelected ? OnboardingPalette.selectedBorder : OnboardingPalette.border, lineWidth: isSelected ? 2 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .modifier(OnboardingSelectedAccessibility(isSelected: isSelected))
    }
}

private struct OnboardingSelectedAccessibility: ViewModifier {
    let isSelected: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isSelected {
            content.accessibilityAddTraits(.isSelected)
        } else {
            content
        }
    }
}

struct OnboardingQuestion<Content: View>: View {
    let subtitle: String
    let contentSpacing: CGFloat
    let content: Content

    init(
        subtitle: String,
        contentSpacing: CGFloat = 24,
        @ViewBuilder content: () -> Content
    ) {
        self.subtitle = subtitle
        self.contentSpacing = contentSpacing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .center, spacing: contentSpacing) {
            Text(subtitle)
                .font(OffRecordTypography.bodyMedium)
                .foregroundStyle(OnboardingPalette.secondaryForeground)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            content
                .frame(maxWidth: .infinity)
        }
    }
}
