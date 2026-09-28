import SwiftUI

struct TodayHeroMetadataChip: View {
    let title: String
    let systemImage: String
    var iconOnly = false
    var fill = OffRecordColor.backgroundSageTint
    var foreground = OffRecordColor.textSage
    var border = OffRecordColor.borderSage

    var body: some View {
        Label {
            if !iconOnly {
                Text(title)
                    .font(OffRecordTypography.labelMedium)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: systemImage)
                .font(OffRecordTypography.labelMedium)
        }
        .labelStyle(.titleAndIcon)
        .foregroundStyle(foreground)
        .padding(.horizontal, iconOnly ? 0 : OffRecordSpacing.md)
        .padding(.vertical, iconOnly ? 0 : OffRecordSpacing.xs)
        .frame(minWidth: OffRecordLayout.minimumTapTarget, minHeight: OffRecordLayout.minimumTapTarget)
        .background(fill.opacity(0.94), in: Capsule())
        .overlay(Capsule().stroke(border, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}
