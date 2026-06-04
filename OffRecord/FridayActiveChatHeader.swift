//
//  FridayActiveChatHeader.swift
//  OffRecord
//
//  Compact active conversation header.
//

import SwiftUI

struct FridayActiveChatHeader: View {
    var body: some View {
        HStack(spacing: OffRecordSpacing.md) {
            FridayMascotView(pose: .listening, size: 42)
                .background(OffRecordColor.backgroundLavenderTint, in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Friday")
                    .font(OffRecordTypography.titleSmall)
                    .foregroundStyle(OffRecordColor.textHeading)

                Label("Private • On device", systemImage: "lock.shield.fill")
                    .font(OffRecordTypography.labelSmall)
                    .foregroundStyle(OffRecordColor.textSage)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, OffRecordSpacing.lg)
        .padding(.vertical, OffRecordSpacing.md)
        .background(OffRecordColor.surfacePrimary.opacity(0.82), in: RoundedRectangle(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .stroke(OffRecordColor.borderSoft, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.04), radius: 18, x: 0, y: 8)
    }
}
