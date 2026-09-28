//
//  FridayActiveChatHeader.swift
//  OffRecord
//
//  Compact active conversation header.
//

import SwiftUI

struct FridayActiveChatHeader: View {
    var onNewChat: (() -> Void)?

    var body: some View {
        HStack(spacing: OffRecordSpacing.md) {
            FridayMascotView(pose: .listening, size: 42)
                .background(OffRecordColor.backgroundLavenderTint, in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: OffRecordSpacing.xxs) {
                Text("Friday")
                    .font(OffRecordTypography.titleSmall)
                    .foregroundStyle(OffRecordColor.textHeading)
                    .accessibilityAddTraits(.isHeader)

                Label("On-device", systemImage: "lock.shield.fill")
                    .font(OffRecordTypography.labelSmall)
                    .foregroundStyle(OffRecordColor.textSage)
            }

            Spacer(minLength: 0)

            if let onNewChat {
                Button(action: onNewChat) {
                    Label("New Chat", systemImage: "square.and.pencil")
                        .labelStyle(.iconOnly)
                        .font(OffRecordTypography.titleSmall)
                        .foregroundStyle(OffRecordColor.textLavender)
                        .frame(width: OffRecordLayout.minimumTapTarget, height: OffRecordLayout.minimumTapTarget)
                        .background(OffRecordColor.backgroundLavenderTint, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New Chat")
                .accessibilityHint("Clears this conversation.")
                .accessibilityIdentifier("friday.newChat")
            }
        }
        .padding(.horizontal, OffRecordSpacing.lg)
        .padding(.vertical, OffRecordSpacing.md)
        .background(OffRecordColor.surfacePrimary.opacity(0.82), in: RoundedRectangle(cornerRadius: OffRecordRadius.xl, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: OffRecordRadius.xl, style: .continuous)
                .stroke(OffRecordColor.borderSoft, lineWidth: 1)
        }
        .offRecordShadow(.chip)
    }
}
