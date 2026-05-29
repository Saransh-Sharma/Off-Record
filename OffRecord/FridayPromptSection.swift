//
//  FridayPromptSection.swift
//  OffRecord
//
//  Suggested prompt layouts for landing and active chat states.
//

import SwiftUI

enum FridayPromptSectionLayout {
    case list
    case grid
}

struct FridayPromptSection: View {
    let title: String
    let questions: [FridayQuestion]
    let askedQuestions: Set<FridayQuestion>
    let layout: FridayPromptSectionLayout
    let action: (FridayQuestion) -> Void

    private let gridColumns = [
        GridItem(.flexible(), spacing: OffRecordSpacing.md),
        GridItem(.flexible(), spacing: OffRecordSpacing.md)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: OffRecordSpacing.lg) {
            Text(title)
                .font(OffRecordTypography.labelLarge)
                .foregroundStyle(OffRecordColor.textBrand)

            switch layout {
            case .list:
                VStack(spacing: OffRecordSpacing.md) {
                    ForEach(questions) { question in
                        FridayPromptPill(
                            question: question,
                            title: question.warmMinimalTitle,
                            isAsked: askedQuestions.contains(question)
                        ) {
                            action(question)
                        }
                    }
                }
            case .grid:
                LazyVGrid(columns: gridColumns, spacing: OffRecordSpacing.md) {
                    ForEach(questions) { question in
                        FridayPromptPill(
                            question: question,
                            title: question.compactPromptTitle,
                            isAsked: askedQuestions.contains(question)
                        ) {
                            action(question)
                        }
                    }
                }
            }
        }
    }
}
