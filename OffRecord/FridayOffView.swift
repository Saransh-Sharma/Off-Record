//
//  FridayOffView.swift
//  OffRecord
//
//  The Friday tab while Friday is turned off in Settings. The tab, the
//  offrecord://friday route, and Ask Friday all land here, and the chat
//  isn't reachable until she's turned back on.
//

import SwiftUI

/// The Friday tab's root: Friday, or her off state.
struct FridayTabRoot: View {
    @AppStorage(FridayAvailability.defaultsKey) private var isFridayEnabled = true

    var body: some View {
        if isFridayEnabled {
            FridayView()
        } else {
            FridayOffView()
        }
    }
}

struct FridayOffView: View {
    @ObservedObject private var navigationRouter = OffRecordNavigationRouter.shared

    var body: some View {
        ScrollView {
            VStack(spacing: OffRecordSpacing.xl) {
                FridayMascotView(pose: .idle, size: 96)
                    .opacity(0.7)
                    .accessibilityHidden(true)

                VStack(spacing: OffRecordSpacing.sm) {
                    Text("Friday Is Off", comment: "Title shown on the Friday tab when Friday is turned off in Settings")
                        .font(OffRecordTypography.titleMedium)
                        .foregroundStyle(OffRecordColor.textHeading)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)

                    Text("Friday doesn’t read your entries while she’s off.")
                        .font(OffRecordTypography.bodyMedium)
                        .foregroundStyle(OffRecordColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    FridayAvailability.turnOn()
                    HapticManager.shared.selectionChanged()
                } label: {
                    Label("Turn On Friday", systemImage: "sparkles")
                        .font(OffRecordTypography.labelLarge)
                        .frame(minHeight: 44)
                        .padding(.horizontal, OffRecordSpacing.lg)
                }
                .buttonStyle(.borderedProminent)
                .tint(OffRecordColor.brandLavenderDark)
                .accessibilityIdentifier("friday.off.turnOn")
            }
            .padding(.horizontal, OffRecordSpacing.screenX)
            .padding(.vertical, OffRecordSpacing.section)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .background(OffRecordAppBackground().ignoresSafeArea())
        .navigationTitle(Text("Friday", comment: "Name of the in-app assistant"))
        .accessibilityIdentifier("friday.off")
        .onAppear { navigationRouter.fridayQuestion = nil }
        .onChange(of: navigationRouter.fridayQuestion) { _, question in
            if question != nil { navigationRouter.fridayQuestion = nil }
        }
    }
}

#Preview {
    NavigationStack { FridayOffView() }
}
