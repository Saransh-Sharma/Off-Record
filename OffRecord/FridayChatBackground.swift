//
//  FridayChatBackground.swift
//  OffRecord
//
//  Soft paper-like background for the Friday chat redesign.
//

import SwiftUI

struct FridayChatBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    OffRecordColor.backgroundPrimary,
                    Color(hex: 0xF8F1F7),
                    OffRecordColor.backgroundPrimary
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack {
                Circle()
                    .fill(OffRecordColor.brandPeach.opacity(0.16))
                    .frame(width: 260, height: 260)
                    .blur(radius: 44)
                    .offset(y: -120)

                Spacer()

                Circle()
                    .fill(OffRecordColor.brandLavender.opacity(0.14))
                    .frame(width: 240, height: 240)
                    .blur(radius: 48)
                    .offset(x: 128, y: -80)
            }
            .accessibilityHidden(true)
        }
        .ignoresSafeArea()
    }
}
