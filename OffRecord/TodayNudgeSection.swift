import SwiftUI

struct TodayNudgeSection: View {
    let prompts: [EntryPrompt]
    let onPrompt: (EntryPrompt) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Need a nudge?")
                .font(OffRecordTypography.labelLarge)
                .foregroundStyle(OffRecordColor.textBrand)
                .accessibilityIdentifier("today.nudgeSection")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(prompts.enumerated()), id: \.element.id) { index, prompt in
                        nudgeCard(prompt: prompt, index: index)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
        }
    }

    @ViewBuilder
    private func nudgeCard(prompt: EntryPrompt, index: Int) -> some View {
        let style = nudgeStyle(for: prompt)
        Button {
            HapticManager.shared.selectionChanged()
            onPrompt(prompt)
        } label: {
            HStack(spacing: 14) {
                OffRecordIconBubble(
                    systemImage: style.systemImage,
                    tint: style.tint,
                    fill: OffRecordColor.surfacePrimary.opacity(0.84),
                    size: 46,
                    iconSize: 18
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(prompt.title)
                        .font(OffRecordTypography.labelLarge)
                        .foregroundStyle(OffRecordColor.textBrand)
                        .lineLimit(1)
                        .minimumScaleFactor(0.86)

                    Text(prompt.detail)
                        .font(OffRecordTypography.metadata)
                        .foregroundStyle(OffRecordColor.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(width: 286, alignment: .leading)
            .frame(minHeight: 88, alignment: .leading)
            .background(style.fill, in: RoundedRectangle(cornerRadius: 22))
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(style.border, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(prompt.title)
        .accessibilityIdentifier("today.nudge.\(index)")
    }

    private func nudgeStyle(for prompt: EntryPrompt) -> TodayNudgeCardStyle {
        switch prompt.title {
        case "Daily reflection":
            return TodayNudgeCardStyle(
                systemImage: "sparkles",
                tint: OffRecordColor.brandLavenderDark,
                fill: OffRecordColor.surfaceLavender,
                border: OffRecordColor.borderSoft
            )
        case "Gratitude":
            return TodayNudgeCardStyle(
                systemImage: "heart.fill",
                tint: OffRecordColor.brandCoral,
                fill: OffRecordColor.surfacePeach,
                border: OffRecordColor.borderWarm
            )
        case "Energy check":
            return TodayNudgeCardStyle(
                systemImage: "bolt.heart.fill",
                tint: OffRecordColor.textAqua,
                fill: OffRecordColor.surfaceMint,
                border: OffRecordColor.borderSage
            )
        case "Letting go":
            return TodayNudgeCardStyle(
                systemImage: "leaf.fill",
                tint: OffRecordColor.brandSageDark,
                fill: OffRecordColor.backgroundSageTint,
                border: OffRecordColor.borderSage
            )
        case "Self-kindness":
            return TodayNudgeCardStyle(
                systemImage: "person.fill.checkmark",
                tint: OffRecordColor.brandLavenderDark,
                fill: OffRecordColor.surfaceLavender,
                border: OffRecordColor.borderSoft
            )
        case "Tomorrow":
            return TodayNudgeCardStyle(
                systemImage: "sunrise.fill",
                tint: OffRecordColor.textPeach,
                fill: OffRecordColor.surfacePeach,
                border: OffRecordColor.borderWarm
            )
        default:
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
