//
//  EntryDetailView+Composer.swift
//  OffRecord
//
//  The composer for a new text block, with the writing prompt above it when
//  the entry opened from one or from a Go Deeper question.
//

import SwiftUI

extension EntryDetailView {
    var newTextBlockComposer: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let promptContext = composerPrompt ?? promptContext, !promptContext.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(OffRecordTypography.labelMedium)
                        .foregroundStyle(OffRecordColor.textLavender)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Writing prompt")
                            .font(OffRecordTypography.labelSmall)
                            .foregroundStyle(OffRecordColor.textPeach)
                        Text(promptContext)
                            .font(OffRecordTypography.bodySmall)
                            .foregroundStyle(OffRecordColor.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }
                .padding(14)
                .offRecordContentCard(cornerRadius: 14, fill: OffRecordColor.surfaceLavender)
            }

            TextEditor(text: $newTextBlockText)
                .font(OffRecordTypography.journalBody)
                .foregroundColor(OffRecordColor.textPrimary)
                .lineSpacing(6)
                .focused($isTextFocused)
                .scrollContentBackground(.hidden)
                .frame(minHeight: isIPad ? 360 : 320)
                .padding(18)
                .background(OffRecordColor.surfaceWarm, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(newTextBlockError == nil ? OffRecordColor.borderWarm : OffRecordColor.brandCoral.opacity(0.42), lineWidth: 1)
                )
                .shadow(color: OffRecordShadow.cardColor, radius: 18, x: 0, y: 8)
                .accessibilityLabel("New text")
                .accessibilityIdentifier("entryDetail.newTextBlock")

            if let newTextBlockError {
                Text(newTextBlockError)
                    .font(OffRecordTypography.metadata)
                    .foregroundColor(OffRecordColor.brandCoral)
            }

            HStack(spacing: 8) {
                Text("^[\(newTextBlockText.split { $0.isWhitespace || $0.isNewline }.count) word](inflect: true)")
                    .font(OffRecordTypography.metadata)
                    .foregroundColor(OffRecordColor.textSecondary)

                Spacer()
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 8)
        .onAppear {
            isTextFocused = true
        }
    }
}
