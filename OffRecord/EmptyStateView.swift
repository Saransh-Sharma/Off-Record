//
//  EmptyStateView.swift
//  OffRecord
//
//  Empty states for the app
//

import SwiftUI

struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: OffRecordSpacing.xxl) {
            illustration
                .accessibilityHidden(true)

            VStack(spacing: OffRecordSpacing.sm) {
                Text(title)
                    .font(OffRecordTypography.titleMedium)
                    .foregroundStyle(OffRecordColor.textHeading)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                Text(subtitle)
                    .font(OffRecordTypography.bodySmall)
                    .foregroundStyle(OffRecordColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 400)
                    .padding(.horizontal, OffRecordSpacing.xxl)
            }

            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    Text(actionTitle)
                        .offRecordPillButton()
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .accessibilityElement(children: .combine)
    }

    /// A soft peach halo behind a lavender disc, with the symbol on top.
    private var illustration: some View {
        ZStack {
            Circle()
                .fill(OffRecordColor.backgroundPeachTint)
                .frame(width: 160, height: 160)

            Circle()
                .fill(OffRecordColor.backgroundLavenderTint)
                .frame(width: 120, height: 120)
                .overlay(Circle().stroke(OffRecordColor.borderSoft, lineWidth: 1))

            floatingSymbol
        }
    }

    @ViewBuilder
    private var floatingSymbol: some View {
        let symbol = Image(systemName: icon)
            .font(OffRecordTypography.screenTitle)
            .imageScale(.large)
            .foregroundStyle(
                LinearGradient(
                    colors: [OffRecordColor.brandLavenderDark, OffRecordColor.brandPeach],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )

        if reduceMotion {
            symbol
        } else {
            symbol.phaseAnimator([false, true]) { content, isUp in
                content.offset(y: isUp ? -6 : 2)
            } animation: { _ in
                .easeInOut(duration: 2.4)
            }
        }
    }
}

// MARK: - Preset Empty States

extension EmptyStateView {
    static var noInsights: EmptyStateView {
        EmptyStateView(
            icon: "chart.line.uptrend.xyaxis",
            title: "No Insights Yet",
            subtitle: "I need 3 entries before I can spot patterns."
        )
    }

    static var fridayGettingToKnow: EmptyStateView {
        EmptyStateView(
            icon: "sparkles",
            title: "Still Getting to Know You",
            subtitle: "After 5 entries, I can start telling you what I see."
        )
    }
}

#Preview {
    EmptyStateView.noInsights
}

