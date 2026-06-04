//
//  FridayPromptStyle.swift
//  OffRecord
//
//  Display labels and pastel styles for Friday prompts.
//

import SwiftUI

struct FridayPromptVisualStyle {
    let fill: Color
    let border: Color
    let accent: Color
}

extension FridayQuestion {
    var warmMinimalTitle: String {
        switch self {
        case .moodPattern:
            return "What has my mood been like?"
        case .talkAboutMost:
            return "Who have I mentioned most?"
        case .dominantTopics:
            return "What keeps showing up?"
        case .stressTriggers:
            return "What has been weighing on me?"
        case .happiestWhen:
            return "What helped me feel better?"
        case .bestJournalTime:
            return "What should I write about today?"
        case .communicationStyle:
            return "Help me unpack how I feel"
        case .moodOverTime:
            return "How has my mood changed?"
        case .positiveOrNegative:
            return "What tone do my entries carry?"
        case .personality:
            return "What do my entries reveal?"
        }
    }

    var compactPromptTitle: String {
        switch self {
        case .moodPattern:
            return "Mood this week"
        case .stressTriggers:
            return "Why might I feel this?"
        case .talkAboutMost:
            return "Who comes up often?"
        case .happiestWhen:
            return "What helps me recover?"
        default:
            return warmMinimalTitle
        }
    }

    var promptStyle: FridayPromptVisualStyle {
        switch self {
        case .moodPattern, .moodOverTime:
            return FridayPromptVisualStyle(
                fill: OffRecordColor.backgroundPeachTint,
                border: OffRecordColor.borderWarm,
                accent: OffRecordColor.textPeach
            )
        case .talkAboutMost, .personality, .communicationStyle:
            return FridayPromptVisualStyle(
                fill: OffRecordColor.backgroundLavenderTint,
                border: OffRecordColor.borderSoft,
                accent: OffRecordColor.textLavender
            )
        case .dominantTopics, .stressTriggers, .positiveOrNegative:
            return FridayPromptVisualStyle(
                fill: OffRecordColor.backgroundSageTint,
                border: OffRecordColor.borderSage,
                accent: OffRecordColor.textSage
            )
        case .happiestWhen, .bestJournalTime:
            return FridayPromptVisualStyle(
                fill: OffRecordColor.surfaceMint,
                border: OffRecordColor.borderSage,
                accent: OffRecordColor.textMint
            )
        }
    }
}
