//
//  EntryDetailView+GoDeeper.swift
//  OffRecord
//
//  The Go Deeper card: one question about the entry, answered by writing or
//  recording, with a button for another question.
//

import SwiftUI

extension EntryDetailView {
    var goDeeperCard: some View {
        VStack(alignment: .leading, spacing: OffRecordSpacing.md) {
            HStack(spacing: OffRecordSpacing.sm) {
                Image(systemName: "sparkles")
                    .foregroundStyle(OffRecordColor.textLavender)
                    .accessibilityHidden(true)
                Text("Go Deeper")
                    .font(OffRecordTypography.labelLarge)
                    .foregroundStyle(OffRecordColor.textHeading)
                Spacer(minLength: 0)
                Button(action: showDeeperQuestion) {
                    Group {
                        if isFetchingDeeperQuestion {
                            ProgressView()
                                .tint(OffRecordColor.textLavender)
                        } else {
                            Image(systemName: deeperQuestion == nil ? "questionmark.bubble" : "arrow.triangle.2.circlepath")
                                .font(OffRecordTypography.labelLarge)
                                .foregroundStyle(OffRecordColor.textLavender)
                                .contentTransition(.symbolEffect(.replace))
                        }
                    }
                    .frame(width: OffRecordLayout.minimumTapTarget, height: OffRecordLayout.minimumTapTarget)
                }
                .buttonStyle(.plain)
                .disabled(isFetchingDeeperQuestion)
                .accessibilityLabel(deeperQuestion == nil ? "Get a Question" : "Another Question")
                .accessibilityIdentifier("entryDetail.goDeeper")
            }

            if let deeperQuestion {
                Text(deeperQuestion)
                    .font(OffRecordTypography.bodyLarge)
                    .foregroundStyle(OffRecordColor.textBrand)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .id(deeperQuestion)

                HStack(spacing: OffRecordSpacing.sm) {
                    Button {
                        composerPrompt = deeperQuestion
                        beginNewTextBlock()
                    } label: {
                        Label(String(localized: "Write", comment: "Button that answers the question by writing."), systemImage: "square.and.pencil")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(OffRecordSoftButtonStyle(tint: OffRecordColor.textBrand, fill: OffRecordColor.surfacePrimary))

                    Button {
                        let capture = CaptureController.shared
                        if let date = entry.date { capture.captureDate = date }
                        capture.startRecording(prompt: deeperQuestion)
                    } label: {
                        Label(String(localized: "Record", comment: "Button that answers the question by recording audio."), systemImage: "mic.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(OffRecordSoftButtonStyle(tint: OffRecordColor.textOnAccent, fill: OffRecordColor.brandPlum))
                }
            } else {
                Text("I’ll ask one question about what you wrote.")
                    .font(OffRecordTypography.bodySmall)
                    .foregroundStyle(OffRecordColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(OffRecordSpacing.lg)
        .offRecordCard(cornerRadius: OffRecordRadius.lg, fill: OffRecordColor.surfaceLavender.opacity(0.7), shadow: false)
    }

    /// The first tap asks for the entry's question (the model's, when it passes
    /// validation); later taps cycle through the templates.
    private func showDeeperQuestion() {
        let provider = GoDeeperQuestionProvider.shared
        guard deeperQuestion != nil else {
            let entryText = text
            let mood = selectedMood
            let allowsModel = FridayEntryIntelligence.isEligible(entry)
            isFetchingDeeperQuestion = true
            Task { @MainActor in
                let question = await provider.firstQuestion(text: entryText, mood: mood, allowsModel: allowsModel)
                isFetchingDeeperQuestion = false
                withOffRecordAnimation(OffRecordMotion.gentle) {
                    deeperQuestion = question
                }
                HapticManager.shared.selectionChanged()
            }
            return
        }
        withOffRecordAnimation(OffRecordMotion.gentle) {
            deeperQuestion = provider.nextQuestion(text: text, mood: selectedMood, excluding: deeperQuestion) ?? deeperQuestion
        }
        HapticManager.shared.selectionChanged()
    }
}
