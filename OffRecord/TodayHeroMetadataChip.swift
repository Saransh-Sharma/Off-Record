import SwiftUI

struct TodayHeroMetadataChip: View {
    let title: String
    let systemImage: String
    var iconOnly = false
    var fill = OffRecordColor.backgroundSageTint
    var foreground = OffRecordColor.textSage
    var border = OffRecordColor.borderSage
    var height: CGFloat = 38

    var body: some View {
        Label {
            if !iconOnly {
                Text(title)
                    .font(OffRecordTypography.labelMedium)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
        } icon: {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, iconOnly ? 0 : 14)
        .frame(width: iconOnly ? height : nil, height: height)
        .background(fill.opacity(0.94), in: Capsule())
        .overlay(Capsule().stroke(border, lineWidth: 1))
        .accessibilityLabel(iconOnly ? title : "\(title)")
    }
}
