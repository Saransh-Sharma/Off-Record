//
//  FridayMessageBubble.swift
//  OffRecord
//
//  Assistant and user bubble styling for Friday chat.
//

import SwiftUI

struct FridayMessageBubble: View {
    let message: FridayChatMessage
    let entryProvider: (UUID) -> DiaryEntry?

    var body: some View {
        HStack(alignment: .top, spacing: OffRecordSpacing.md) {
            if message.isUser {
                Spacer(minLength: 54)
            } else {
                FridayMascotView(pose: .thinking, size: 40)
                    .padding(.top, 18)
                    .accessibilityHidden(true)
            }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: OffRecordSpacing.sm) {
                if !message.isUser {
                    Text("Friday")
                        .font(OffRecordTypography.labelSmall)
                        .foregroundStyle(OffRecordColor.textLavender)
                        .padding(.leading, 4)
                }

                Text(message.text)
                    .font(OffRecordTypography.bodyMedium)
                    .lineSpacing(3)
                    .foregroundStyle(message.isUser ? OffRecordColor.textBrand : OffRecordColor.textBrand.opacity(0.88))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: message.isUser ? 260 : 286, alignment: message.isUser ? .trailing : .leading)
                    .background(message.isUser ? userBubbleFill : assistantBubbleFill, in: RoundedRectangle(cornerRadius: 22))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22)
                            .stroke(message.isUser ? OffRecordColor.borderSoft.opacity(0.5) : OffRecordColor.borderSoft, lineWidth: 1)
                    }
                    .shadow(color: Color.black.opacity(message.isUser ? 0.02 : 0.04), radius: 18, x: 0, y: 6)
                    .overlay(alignment: .bottomTrailing) {
                        if message.isUser {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(OffRecordColor.textLavender)
                                .frame(width: 20, height: 20)
                                .background(OffRecordColor.backgroundLavenderTint, in: Circle())
                                .offset(x: 8, y: 8)
                                .accessibilityHidden(true)
                        }
                    }
                    .accessibilityIdentifier(message.isUser ? "friday.userMessage" : "friday.answerMessage")

                if !message.isUser {
                    if let limitations = message.limitations {
                        Text(limitations)
                            .font(OffRecordTypography.metadata)
                            .foregroundStyle(OffRecordColor.textSecondary)
                            .padding(.horizontal, 4)
                            .accessibilityIdentifier("friday.limitations")
                    }

                    if !message.evidence.isEmpty {
                        FridayEvidenceRail(evidence: message.evidence, entryProvider: entryProvider)
                    }
                }
            }

            if !message.isUser {
                Spacer(minLength: 28)
            }
        }
    }

    private var assistantBubbleFill: Color {
        OffRecordColor.surfacePrimary.opacity(0.96)
    }

    private var userBubbleFill: Color {
        OffRecordColor.backgroundLavenderTint
    }
}
