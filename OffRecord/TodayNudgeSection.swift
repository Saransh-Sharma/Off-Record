import SwiftUI

struct TodayNudgeSection: View {
    let prompts: [EntryPrompt]
    let onWrite: (EntryPrompt) -> Void
    let onSpeak: (EntryPrompt) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var cardWidth: CGFloat = 292

    var body: some View {
        VStack(alignment: .leading, spacing: OffRecordSpacing.md) {
            Text("Need a nudge?")
                .font(OffRecordTypography.sectionTitle)
                .foregroundStyle(OffRecordColor.textHeading)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("today.nudgeSection")

            ScrollView(.horizontal) {
                LazyHStack(spacing: OffRecordSpacing.md) {
                    ForEach(Array(prompts.enumerated()), id: \.element.id) { index, prompt in
                        nudgeCard(prompt: prompt, index: index)
                            .scrollTransition(.interactive, axis: .horizontal) { card, phase in
                                card
                                    .scaleEffect(reduceMotion || phase.isIdentity ? 1 : 0.94)
                                    .opacity(phase.isIdentity ? 1 : 0.75)
                            }
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
        }
    }

    @ViewBuilder
    private func nudgeCard(prompt: EntryPrompt, index: Int) -> some View {
        let style = nudgeStyle(for: prompt)
        VStack(alignment: .leading, spacing: OffRecordSpacing.md) {
            HStack(alignment: .top, spacing: OffRecordSpacing.md) {
                OffRecordIconBubble(
                    systemImage: style.systemImage,
                    tint: style.tint,
                    fill: OffRecordColor.surfacePrimary.opacity(0.84),
                    size: 42,
                    iconSize: 17
                )

                VStack(alignment: .leading, spacing: OffRecordSpacing.xs) {
                    Text(prompt.title)
                        .font(OffRecordTypography.labelLarge)
                        .foregroundStyle(OffRecordColor.textBrand)
                    Text(prompt.detail)
                        .font(OffRecordTypography.metadata)
                        .foregroundStyle(OffRecordColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel(for: prompt))

            HStack(spacing: OffRecordSpacing.sm) {
                Button {
                    HapticManager.shared.selectionChanged()
                    onSpeak(prompt)
                } label: {
                    Label("Speak", systemImage: "mic.fill")
                        .font(OffRecordTypography.labelSmall)
                        .foregroundStyle(OffRecordColor.textOnAccent)
                        .padding(.horizontal, OffRecordSpacing.md)
                        .frame(minHeight: OffRecordLayout.minimumTapTarget)
                        .background(OffRecordColor.brandPlum, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Speak about \(prompt.title)")

                Button {
                    HapticManager.shared.selectionChanged()
                    onWrite(prompt)
                } label: {
                    Label("Write", systemImage: "square.and.pencil")
                        .font(OffRecordTypography.labelSmall)
                        .foregroundStyle(OffRecordColor.textBrand)
                        .padding(.horizontal, OffRecordSpacing.md)
                        .frame(minHeight: OffRecordLayout.minimumTapTarget)
                        .background(OffRecordColor.surfacePrimary.opacity(0.8), in: Capsule())
                        .overlay(Capsule().stroke(style.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Write about \(prompt.title)")
                .accessibilityIdentifier("today.nudge.\(index)")
            }
        }
        .padding(OffRecordSpacing.lg)
        .frame(width: min(cardWidth, 360), alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(style.fill, in: RoundedRectangle(cornerRadius: OffRecordRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: OffRecordRadius.lg, style: .continuous)
                .stroke(style.border, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    private func accessibilityLabel(for prompt: EntryPrompt) -> String {
        let detail = prompt.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        return detail.isEmpty ? prompt.title : "\(prompt.title): \(detail)"
    }

    private func nudgeStyle(for prompt: EntryPrompt) -> TodayNudgeCardStyle {
        switch prompt.kind {
        case .dailyReflection:
            return TodayNudgeCardStyle(
                systemImage: "sparkles",
                tint: OffRecordColor.brandLavenderDark,
                fill: OffRecordColor.surfaceLavender,
                border: OffRecordColor.borderSoft
            )
        case .gratitude:
            return TodayNudgeCardStyle(
                systemImage: "heart.fill",
                tint: OffRecordColor.brandCoral,
                fill: OffRecordColor.surfacePeach,
                border: OffRecordColor.borderWarm
            )
        case .energyCheck:
            return TodayNudgeCardStyle(
                systemImage: "bolt.heart.fill",
                tint: OffRecordColor.textAqua,
                fill: OffRecordColor.surfaceMint,
                border: OffRecordColor.borderSage
            )
        case .lettingGo:
            return TodayNudgeCardStyle(
                systemImage: "leaf.fill",
                tint: OffRecordColor.brandSageDark,
                fill: OffRecordColor.backgroundSageTint,
                border: OffRecordColor.borderSage
            )
        case .selfKindness:
            return TodayNudgeCardStyle(
                systemImage: "person.fill.checkmark",
                tint: OffRecordColor.brandLavenderDark,
                fill: OffRecordColor.surfaceLavender,
                border: OffRecordColor.borderSoft
            )
        case .tomorrow:
            return TodayNudgeCardStyle(
                systemImage: "sunrise.fill",
                tint: OffRecordColor.textPeach,
                fill: OffRecordColor.surfacePeach,
                border: OffRecordColor.borderWarm
            )
        case .custom:
            return TodayNudgeCardStyle(
                systemImage: "square.and.pencil",
                tint: OffRecordColor.textBrand,
                fill: OffRecordColor.surfaceWarm,
                border: OffRecordColor.borderSoft
            )
        }
    }
}

private struct TodayNudgeCardStyle {
    let systemImage: String
    let tint: Color
    let fill: Color
    let border: Color
}
