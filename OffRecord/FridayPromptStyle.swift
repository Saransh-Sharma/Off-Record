//
//  FridayPromptStyle.swift
//  OffRecord
//
//  Pastel styles for Friday prompts.
//

import SwiftUI

struct FridayPromptVisualStyle {
    let fill: Color
    let border: Color
    let accent: Color
}

extension FridayQuestion {
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
