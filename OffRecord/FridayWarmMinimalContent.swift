//
//  FridayWarmMinimalContent.swift
//  OffRecord
//
//  Landing content for Friday chat before a conversation starts.
//

import SwiftUI

enum FridayWarmMinimalMode {
    case warm
    case noJournalData
    case indexing(String)
}

struct FridayWarmMinimalContent: View {
    let userName: String
    let questions: [FridayQuestion]
    let askedQuestions: Set<FridayQuestion>
    let mode: FridayWarmMinimalMode
    let action: (FridayQuestion) -> Void

    var body: some View {
        VStack(spacing: 0) {
            FridayChatHeroHeader(subtitle: subtitle)
                .padding(.bottom, 20)

            mascotHero
                .padding(.bottom, -18)
                .zIndex(1)

            FridayIntroCard(userName: userName, mode: mode)
                .padding(.horizontal, cardHorizontalInset)
                .padding(.bottom, 28)

            FridayPromptSection(
                title: promptTitle,
                questions: questions,
                askedQuestions: askedQuestions,
                layout: .list,
                action: action
            )
            .padding(.horizontal, promptHorizontalInset)
        }
    }

    private var mascotHero: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            OffRecordColor.brandPeach.opacity(0.22),
                            OffRecordColor.brandBlush.opacity(0.12),
                            .clear
                        ],
                        center: .center,
                        startRadius: 24,
                        endRadius: 116
                    )
                )
                .frame(width: 168, height: 168)
                .accessibilityHidden(true)

            FridayMascotView(pose: .confiding, size: 150)
                .accessibilityHidden(true)
        }
    }

    private var subtitle: String {
        switch mode {
        case .noJournalData:
            return "Your private journal companion is ready when you have a little more to reflect on."
        case .indexing:
            return "I’m preparing your private journal memory so I can answer with care."
        case .warm:
            return "Your private journal companion for patterns, moods, and moments you want to understand."
        }
    }

    private var promptTitle: String {
        switch mode {
        case .noJournalData:
            return "You can start with"
        case .indexing, .warm:
            return "Things you can ask"
        }
    }

    private var cardHorizontalInset: CGFloat {
        16
    }

    private var promptHorizontalInset: CGFloat {
        4
    }
}
