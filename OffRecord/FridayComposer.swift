//
//  FridayComposer.swift
//  OffRecord
//
//  Floating composer for Friday chat.
//

import SwiftUI

struct FridayComposer: View {
    @Binding var text: String
    let isAnswering: Bool
    let isIndexing: Bool
    let indexingProgress: Double
    let indexingMessage: String
    let onSend: () -> Void

    var body: some View {
        VStack(spacing: OffRecordSpacing.sm) {
            if isIndexing {
                indexingStatus
            }

            HStack(alignment: .bottom, spacing: OffRecordSpacing.sm) {
                TextField("Ask Friday about your journal...", text: $text, axis: .vertical)
                    .font(OffRecordTypography.bodyMedium)
                    .foregroundStyle(OffRecordColor.textPrimary)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .padding(.leading, 20)
                    .padding(.vertical, 16)
                    .disabled(isAnswering)
                    .accessibilityLabel("Message Friday")
                    .accessibilityIdentifier("friday.askField")

                Button(action: onSend) {
                    Image(systemName: isAnswering ? "hourglass" : "arrow.right")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(OffRecordColor.textInverse)
                        .frame(width: 48, height: 48)
                        .background(canSend ? OffRecordColor.brandLavenderDark : OffRecordColor.brandLavender, in: Circle())
                }
                .disabled(!canSend)
                .buttonStyle(.plain)
                .accessibilityLabel("Send message")
                .accessibilityIdentifier("friday.askButton")
                .padding(.trailing, 6)
                .padding(.bottom, 6)
            }
            .frame(minHeight: 60)
            .background(OffRecordColor.surfacePrimary.opacity(0.97), in: RoundedRectangle(cornerRadius: 30))
            .overlay {
                RoundedRectangle(cornerRadius: 30)
                    .stroke(OffRecordColor.borderSoft, lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.08), radius: 24, x: 0, y: 8)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("friday.composer")
        }
        .padding(.horizontal, OffRecordSpacing.xxl)
        .padding(.top, OffRecordSpacing.sm)
        .background(OffRecordColor.backgroundPrimary.opacity(0.98).ignoresSafeArea())
    }

    private var indexingStatus: some View {
        HStack(spacing: OffRecordSpacing.sm) {
            ProgressView(value: indexingProgress)
                .frame(width: 70)

            Text(indexingMessage)
                .font(OffRecordTypography.metadata)
                .foregroundStyle(OffRecordColor.textSecondary)
                .lineLimit(2)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, OffRecordSpacing.lg)
        .padding(.vertical, OffRecordSpacing.sm)
        .background(OffRecordColor.surfaceWarm.opacity(0.96), in: Capsule())
        .overlay {
            Capsule().stroke(OffRecordColor.borderSoft, lineWidth: 1)
        }
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isAnswering && !isIndexing
    }
}
