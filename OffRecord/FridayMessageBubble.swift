//
//  FridayMessageBubble.swift
//  OffRecord
//
//  Assistant and user bubble styling for Friday chat. Friday's answers reveal
//  sentence by sentence (generation isn't streamed), carry numbered citation
//  markers that match the evidence chips, and show how strong the evidence is.
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

struct FridayMessageBubble: View {
    let message: FridayChatMessage
    let isRevealing: Bool
    let showsFollowUps: Bool
    let bubbleMaxWidth: CGFloat
    let namespace: Namespace.ID
    let entryProvider: (UUID) -> DiaryEntry?
    let onRevealFinished: () -> Void
    let onFollowUp: (FridayFollowUp) -> Void
    let onOpenEvidence: (FridayEvidenceSelection) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealedCount: Int
    @State private var copyTrigger = 0

    init(
        message: FridayChatMessage,
        isRevealing: Bool,
        showsFollowUps: Bool,
        bubbleMaxWidth: CGFloat,
        namespace: Namespace.ID,
        entryProvider: @escaping (UUID) -> DiaryEntry?,
        onRevealFinished: @escaping () -> Void,
        onFollowUp: @escaping (FridayFollowUp) -> Void,
        onOpenEvidence: @escaping (FridayEvidenceSelection) -> Void
    ) {
        self.message = message
        self.isRevealing = isRevealing
        self.showsFollowUps = showsFollowUps
        self.bubbleMaxWidth = bubbleMaxWidth
        self.namespace = namespace
        self.entryProvider = entryProvider
        self.onRevealFinished = onRevealFinished
        self.onFollowUp = onFollowUp
        self.onOpenEvidence = onOpenEvidence
        _revealedCount = State(initialValue: isRevealing ? 0 : .max)
    }

    private var segments: [FridayAnswerSegment] { message.segments }
    private var isFullyRevealed: Bool { revealedCount >= segments.count }

    var body: some View {
        if message.isUser {
            userBubble
        } else {
            assistantBubble
        }
    }

    // MARK: User

    private var userBubble: some View {
        HStack {
            Spacer(minLength: 0)

            Text(message.summary)
                .font(OffRecordTypography.bodyMedium)
                .lineSpacing(3)
                .foregroundStyle(OffRecordColor.textBrand)
                .padding(.horizontal, OffRecordSpacing.lg)
                .padding(.vertical, 14)
                .background(OffRecordColor.backgroundLavenderTint, in: bubbleShape)
                .overlay { bubbleShape.stroke(OffRecordColor.borderSoft.opacity(0.5), lineWidth: 1) }
                .contextMenu { messageActions }
                .frame(maxWidth: bubbleMaxWidth, alignment: .trailing)
                .accessibilityLabel("You: \(message.summary)")
                .accessibilityIdentifier("friday.userMessage.\(message.id.uuidString)")
        }
        .sensoryFeedback(.success, trigger: copyTrigger)
    }

    // MARK: Friday

    private var assistantBubble: some View {
        HStack(alignment: .top, spacing: OffRecordSpacing.md) {
            FridayMascotView(pose: .thinking, size: 40)
                .padding(.top, 18)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: OffRecordSpacing.sm) {
                Text("Friday")
                    .font(OffRecordTypography.labelSmall)
                    .foregroundStyle(OffRecordColor.textLavender)
                    .padding(.leading, OffRecordSpacing.xs)
                    .accessibilityHidden(true)

                answerText
                    .frame(maxWidth: bubbleMaxWidth, alignment: .leading)

                if isFullyRevealed {
                    details
                        .transition(.opacity.combined(with: .offset(y: 6)))
                }
            }

            Spacer(minLength: 0)
        }
        .task(id: message.id) {
            await revealIfNeeded()
        }
        .sensoryFeedback(.success, trigger: copyTrigger)
    }

    private var answerText: some View {
        Text(FridayAnswerComposer.attributedText(
            segments,
            revealedCount: revealedCount,
            textColor: OffRecordColor.textPrimary,
            markerColor: OffRecordColor.textLavender
        ))
        .font(OffRecordTypography.bodyMedium)
        .lineSpacing(3)
        .contentTransition(.opacity)
        .textSelection(.enabled)
        .padding(.horizontal, OffRecordSpacing.lg)
        .padding(.vertical, 14)
        .background(OffRecordColor.surfacePrimary.opacity(0.96), in: bubbleShape)
        .overlay { bubbleShape.stroke(OffRecordColor.borderSoft, lineWidth: 1) }
        .offRecordShadow(.chip)
        .contextMenu { messageActions }
        .accessibilityLabel("Friday: \(message.text)")
        .accessibilityHint(hasCitations ? "Numbers in brackets match the sources listed below." : "")
        .accessibilityIdentifier("friday.answerMessage.\(message.id.uuidString)")
    }

    @ViewBuilder
    private var details: some View {
        if let strength = message.evidenceStrength {
            FridayEvidenceStrengthChip(strength: strength)
        }

        if let limitations = message.limitations, !limitations.isEmpty {
            Text(limitations)
                .font(OffRecordTypography.metadata)
                .foregroundStyle(OffRecordColor.textSecondary)
                .padding(.horizontal, OffRecordSpacing.xs)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("friday.limitations")
        }

        if !message.evidence.isEmpty {
            FridayEvidenceRail(
                messageID: message.id,
                evidence: message.evidence,
                maxWidth: bubbleMaxWidth,
                namespace: namespace,
                entryProvider: entryProvider,
                onOpen: onOpenEvidence
            )
        }

        if showsFollowUps && !message.followUps.isEmpty {
            FridayFollowUpChips(followUps: message.followUps, action: onFollowUp)
                .padding(.top, OffRecordSpacing.xs)
        }
    }

    @ViewBuilder
    private var messageActions: some View {
        Button {
            #if os(iOS)
            UIPasteboard.general.string = message.text
            #endif
            copyTrigger += 1
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }

        ShareLink(item: message.text) {
            Label("Share", systemImage: "square.and.arrow.up")
        }
    }

    private var hasCitations: Bool {
        segments.contains { !$0.citations.isEmpty }
    }

    private var bubbleShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: OffRecordRadius.lg, style: .continuous)
    }

    // MARK: Reveal

    /// Reveals the answer a sentence at a time over roughly 0.6–1.2s. Reduce Motion shows it at once.
    private func revealIfNeeded() async {
        guard isRevealing, !isFullyRevealed else { return }
        let count = segments.count
        guard !reduceMotion, count > 1 else {
            revealedCount = count
            onRevealFinished()
            return
        }

        let total = min(1.2, max(0.6, Double(count) * 0.22))
        let step = total / Double(count)
        revealedCount = 1
        for index in 2...count {
            try? await Task.sleep(for: .seconds(step))
            if Task.isCancelled { break }
            withAnimation(OffRecordMotion.fade) {
                revealedCount = index
            }
        }
        revealedCount = count
        onRevealFinished()
    }
}

// MARK: - Evidence strength chip

struct FridayEvidenceStrengthChip: View {
    let strength: FridayEvidenceStrength

    var body: some View {
        Label(strength.title, systemImage: strength.systemImage)
            .font(OffRecordTypography.labelSmall)
            .labelStyle(.titleAndIcon)
            .offRecordReadablePill(strength.style, horizontalPadding: 10, verticalPadding: 5)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(strength.accessibilityLabel)
            .accessibilityIdentifier("friday.evidenceStrength")
    }
}

// MARK: - Follow-up chips

struct FridayFollowUpChips: View {
    let followUps: [FridayFollowUp]
    let action: (FridayFollowUp) -> Void

    @State private var tapTrigger = 0

    var body: some View {
        VStack(alignment: .leading, spacing: OffRecordSpacing.sm) {
            Text("Keep exploring")
                .font(OffRecordTypography.labelSmall)
                .foregroundStyle(OffRecordColor.textSecondary)
                .padding(.leading, OffRecordSpacing.xs)
                .accessibilityAddTraits(.isHeader)

            FlowLayout(spacing: OffRecordSpacing.sm) {
                ForEach(followUps) { followUp in
                    Button {
                        tapTrigger += 1
                        action(followUp)
                    } label: {
                        Label(followUp.title, systemImage: "arrow.turn.down.right")
                            .labelStyle(.titleAndIcon)
                            .font(OffRecordTypography.labelMedium)
                            .foregroundStyle(OffRecordColor.textLavender)
                            .padding(.horizontal, 14)
                            .frame(minHeight: OffRecordLayout.minimumTapTarget)
                            .background(OffRecordColor.backgroundLavenderTint, in: Capsule())
                            .overlay(Capsule().stroke(OffRecordColor.borderSoft, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .offRecordPointerLift()
                    .accessibilityLabel("Ask Friday: \(followUp.prompt)")
                    .accessibilityIdentifier("friday.followUp.\(followUp.accessibilityID)")
                }
            }
        }
        .sensoryFeedback(.selection, trigger: tapTrigger)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("friday.followUps")
    }
}
