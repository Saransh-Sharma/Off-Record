//
//  FridayBackButton.swift
//  OffRecord
//
//  Floating navigation control for Friday chat.
//

import SwiftUI

struct FridayBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Back", systemImage: "chevron.left")
                .labelStyle(.iconOnly)
                .font(OffRecordTypography.titleSmall)
                .foregroundStyle(OffRecordColor.textBrand)
                .frame(width: FridayChatLayout.minimumTapTarget, height: FridayChatLayout.minimumTapTarget)
                .background(OffRecordColor.surfacePrimary.opacity(0.94), in: Circle())
                .offRecordShadow(.chip)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
        .accessibilityIdentifier("friday.backButton")
    }
}
