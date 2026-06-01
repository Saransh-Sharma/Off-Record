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
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(OffRecordColor.brandPlum)
                .frame(width: FridayChatLayout.minimumTapTarget, height: FridayChatLayout.minimumTapTarget)
                .background(OffRecordColor.surfacePrimary.opacity(0.94), in: Circle())
                .shadow(color: Color.black.opacity(0.06), radius: 14, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
        .accessibilityIdentifier("friday.backButton")
    }
}
