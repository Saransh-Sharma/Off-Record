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
    let revealingMessageID: UUID?
    let showsFollowUps: Bool
    let bubbleMaxWidth: CGFloat
    let namespace: Namespace.ID
    let entryProvider: (UUID) -> DiaryEntry?
    let onRevealFinished: (UUID) -> Void
    let onFollowUp: (FridayFollowUp) -> Void
    let onOpenEvidence: (FridayEvidenceSelection) -> Void

    var body: some View {
        LazyVStack(spacing: 18) {
            ForEach(messages) { message in
                FridayMessageBubble(
                    message: message,
                    isRevealing: message.id == revealingMessageID,
                    showsFollowUps: showsFollowUps && message.id == lastAnswerID,
                    bubbleMaxWidth: bubbleMaxWidth,
                    namespace: namespace,
                    entryProvider: entryProvider,
                    onRevealFinished: { onRevealFinished(message.id) },
                    onFollowUp: onFollowUp,
                    onOpenEvidence: onOpenEvidence
                )
            }

            if isAnswering {
                FridayTypingIndicator()
                    .transition(.opacity)
            }
        }
    }

    /// Follow-ups only belong to the latest answer, and only when it ends the thread.
    private var lastAnswerID: UUID? {
        guard let last = messages.last, !last.isUser else { return nil }
        return last.id
    }
}
