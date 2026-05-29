//
//  FridayMessageList.swift
//  OffRecord
//
//  Active Friday conversation body.
//

import SwiftUI

struct FridayMessageList: View {
    let messages: [FridayChatMessage]
    let isAnswering: Bool
    let entryProvider: (UUID) -> DiaryEntry?

    var body: some View {
        LazyVStack(spacing: 18) {
            ForEach(messages) { message in
                FridayMessageBubble(message: message, entryProvider: entryProvider)
            }

            if isAnswering {
                FridayTypingIndicator()
            }
        }
    }
}
