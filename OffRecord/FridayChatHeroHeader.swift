//
//  FridayChatHeroHeader.swift
//  OffRecord
//
//  Centered Friday chat header.
//

import SwiftUI

struct FridayChatHeroHeader: View {
    let subtitle: String

    var body: some View {
        VStack(spacing: OffRecordSpacing.md) {
            Text("Talk to Friday")
                .font(OffRecordTypography.screenTitle)
                .foregroundStyle(OffRecordColor.textHeading)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(subtitle)
                .font(OffRecordTypography.bodyMedium)
                .foregroundStyle(OffRecordColor.textBrand.opacity(0.78))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 305)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }
}
